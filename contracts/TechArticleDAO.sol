// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 导入 OpenZeppelin 的访问控制和代币接口合约
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title TechArticleDAO - 易登技术社区文章评审和奖励系统
/// @dev 继承 AccessControl 以实现角色管理功能
contract TechArticleDAO is AccessControl {
    // ============ 角色和合约实例 ============

    /// @dev 使用哈希值定义评审者角色的标识符
    bytes32 public constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");

    /// @dev YD代币合约接口，用于处理奖励发放
    IERC20 public yiDengToken;

    // ============ 状态定义 ============

    /// @dev 定义文章的三种状态：待评审、已通过、已拒绝
    enum ArticleStatus {
        Pending, // 待评审状态：文章刚提交或正在评审中
        Approved, // 已通过状态：文章评审通过且奖励已发放
        Rejected // 已拒绝状态：文章未通过评审
    }

    /// @dev 文章的完整信息结构
    struct Article {
        uint256 id; // 文章的唯一标识符，从1开始递增
        address author; // 文章作者的以太坊地址
        string title; // 文章标题
        string contentHash; // 文章内容的IPFS哈希值
        string courseId; // 文章关联的视频课程ID
        uint256 submissionTime; // 文章提交的时间戳
        uint256 votesFor; // 获得的赞成票数
        uint256 votesAgainst; // 获得的反对票数
        uint256 rewardAmount; // 文章可获得的奖励金额（基于评分动态计算）
        ArticleStatus status; // 文章当前的状态
        mapping(address => bool) hasVoted; // 记录每个评审者的投票情况，防止重复投票
    }

    // ============ 常量配置 ============

    /// @dev 定义投票持续时间为7天（以秒为单位）
    uint256 public constant VOTING_DURATION = 7 days;

    /// @dev 完成评审所需的最小投票数，至少需要3票
    uint256 public constant MIN_VOTES_REQUIRED = 3;

    /// @dev 文章通过所需的最小赞成率（70%）
    uint256 public constant MIN_APPROVAL_RATE = 70;

    /// @dev 每篇文章的基础奖励金额（100个YD代币，包含18位小数）
    uint256 public constant BASE_REWARD = 100 * 10 ** 18;

    // ============ 存储变量 ============

    /// @dev 存储所有文章的映射：文章ID => 文章信息
    mapping(uint256 => Article) public articles;

    /// @dev 记录已提交的文章总数，同时用作文章ID生成器
    uint256 public articleCount;

    // ============ 事件定义 ============

    /// @dev 当新文章被提交时触发
    event ArticleSubmitted(
        uint256 indexed articleId, // 文章ID（用于索引和查询）
        address indexed author, // 作者地址（用于索引和查询）
        string title // 文章标题
    );

    /// @dev 当评审者对文章进行投票时触发
    event ArticleVoted(
        uint256 indexed articleId, // 文章ID
        address indexed reviewer, // 评审者地址
        bool support // 投票类型（true表示赞成，false表示反对）
    );

    /// @dev 当文章状态发生改变时触发
    event ArticleStatusUpdated(
        uint256 indexed articleId, // 文章ID
        ArticleStatus status // 文章的新状态
    );

    /// @dev 当向作者发放奖励时触发
    event RewardPaid(
        uint256 indexed articleId, // 文章ID
        address indexed author, // 作者地址
        uint256 amount // 奖励金额（YD代币数量）
    );

    // ============ 构造函数 ============

    /// @dev 部署合约时初始化YD代币合约地址和角色设置
    /// @param _tokenAddress YD代币合约的地址
    constructor(address _tokenAddress) {
        // 确保代币合约地址不为零地址
        require(_tokenAddress != address(0), "Invalid token address");

        // 初始化YD代币合约实例
        yiDengToken = IERC20(_tokenAddress);

        // 将合约部署者设置为管理员角色
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);

        // 将合约部署者设置为初始评审者
        _grantRole(REVIEWER_ROLE, msg.sender);
    }

    // ============ 主要功能函数 ============

    /// @dev 提交新的技术文章进行评审
    /// @param title 文章标题
    /// @param contentHash 文章内容的IPFS哈希值
    /// @param courseId 关联的视频课程ID
    function submitArticle(
        string memory title,
        string memory contentHash,
        string memory courseId
    ) external {
        // 验证所有输入参数不能为空
        require(bytes(title).length > 0, "Title cannot be empty");
        require(bytes(contentHash).length > 0, "Content hash cannot be empty");
        require(bytes(courseId).length > 0, "Course ID cannot be empty");

        // 增加文章计数器
        articleCount++;

        // 获取新文章的存储引用
        Article storage newArticle = articles[articleCount];

        // 初始化文章信息
        newArticle.id = articleCount; // 设置文章ID
        newArticle.author = msg.sender; // 设置作者地址
        newArticle.title = title; // 设置文章标题
        newArticle.contentHash = contentHash; // 设置内容哈希
        newArticle.courseId = courseId; // 设置课程ID
        newArticle.submissionTime = block.timestamp; // 记录提交时间
        newArticle.status = ArticleStatus.Pending; // 设置初始状态为待评审

        // 触发文章提交事件
        emit ArticleSubmitted(articleCount, msg.sender, title);
    }

    /// @dev 评审者对文章进行投票和评分
    /// @param articleId 要评审的文章ID
    /// @param support true表示赞成，false表示反对
    /// @param qualityScore 文章质量评分（0-100分）
    function reviewArticle(
        uint256 articleId,
        bool support,
        uint8 qualityScore
    ) external onlyRole(REVIEWER_ROLE) {
        // 验证文章ID是否有效
        require(
            articleId > 0 && articleId <= articleCount,
            "Invalid article ID"
        );
        // 验证质量评分是否在有效范围内
        require(qualityScore <= 100, "Invalid quality score");

        // 获取文章信息
        Article storage article = articles[articleId];

        // 检查文章是否处于待评审状态
        require(article.status == ArticleStatus.Pending, "Article not pending");
        // 检查评审者是否已经投票过
        require(!article.hasVoted[msg.sender], "Already voted");
        // 检查是否在投票有效期内
        require(
            block.timestamp <= article.submissionTime + VOTING_DURATION,
            "Voting period ended"
        );

        // 记录评审者已投票
        article.hasVoted[msg.sender] = true;

        // 根据投票类型更新计数并计算奖励
        if (support) {
            // 增加赞成票计数
            article.votesFor++;
            // 根据质量评分计算奖励金额
            article.rewardAmount += (BASE_REWARD * qualityScore) / 100;
        } else {
            // 增加反对票计数
            article.votesAgainst++;
        }

        // 触发投票事件
        emit ArticleVoted(articleId, msg.sender, support);

        // 检查是否满足评审完成条件
        checkAndFinalizeVoting(articleId);
    }

    /// @dev 检查投票是否完成并处理文章最终状态
    /// @param articleId 文章ID
    function checkAndFinalizeVoting(uint256 articleId) internal {
        // 获取文章信息
        Article storage article = articles[articleId];

        // 计算总投票数
        uint256 totalVotes = article.votesFor + article.votesAgainst;

        // 检查是否达到最小投票数要求
        if (totalVotes >= MIN_VOTES_REQUIRED) {
            // 计算赞成率（百分比）
            uint256 approvalRate = (article.votesFor * 100) / totalVotes;

            if (approvalRate >= MIN_APPROVAL_RATE) {
                // 文章通过评审
                article.status = ArticleStatus.Approved;

                // 检查合约是否有足够的代币支付奖励
                require(
                    yiDengToken.balanceOf(address(this)) >=
                        article.rewardAmount,
                    "Insufficient reward balance"
                );

                // 发放奖励代币给作者
                require(
                    yiDengToken.transfer(article.author, article.rewardAmount),
                    "Reward transfer failed"
                );

                // 触发奖励发放事件
                emit RewardPaid(
                    articleId,
                    article.author,
                    article.rewardAmount
                );
            } else {
                // 文章未通过评审
                article.status = ArticleStatus.Rejected;
            }

            // 触发状态更新事件
            emit ArticleStatusUpdated(articleId, article.status);
        }
    }

    // ============ 查询函数 ============

    // @dev 获取文章的完整信息
    // @param articleId 文章ID
    // @return 文章的所有字段信息
    function getArticle(
        uint256 articleId
    )
        external
        view
        returns (
            address author,
            string memory title,
            string memory contentHash,
            string memory courseId,
            uint256 submissionTime,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 rewardAmount,
            ArticleStatus status
        )
    {
        // 获取文章存储引用
        Article storage article = articles[articleId];

        // 返回文章的所有信息
        return (
            article.author,
            article.title,
            article.contentHash,
            article.courseId,
            article.submissionTime,
            article.votesFor,
            article.votesAgainst,
            article.rewardAmount,
            article.status
        );
    }

    /// @dev 检查指定评审者是否已对文章投票
    /// @param articleId 文章ID
    /// @param voter 评审者地址
    /// @return bool 是否已投票
    function hasVoted(
        uint256 articleId,
        address voter
    ) external view returns (bool) {
        return articles[articleId].hasVoted[voter];
    }

    // ============ 角色管理函数 ============

    /// @dev 添加新的评审者
    /// @param account 要添加的评审者地址
    function addReviewer(
        address account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(REVIEWER_ROLE, account);
    }

    /// @dev 移除评审者
    /// @param account 要移除的评审者地址
    function removeReviewer(
        address account
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(REVIEWER_ROLE, account);
    }

    /// @dev 检查地址是否是评审者
    /// @param account 要检查的地址
    /// @return bool 是否是评审者
    function isReviewer(address account) external view returns (bool) {
        return hasRole(REVIEWER_ROLE, account);
    }
}

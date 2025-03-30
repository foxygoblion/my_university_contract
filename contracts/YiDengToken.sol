// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// 导入 OpenZeppelin 的 ERC20 标准合约
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// 导入 OpenZeppelin 的所有权控制合约
import "@openzeppelin/contracts/access/Ownable.sol";

// YiDengToken 合约，继承自 ERC20 和 Ownable
contract YiDengToken is ERC20, Ownable {
    // 定义 ETH 兑换 YD 的比率：1 ETH = 1000 YD
    uint256 public constant TOKENS_PER_ETH = 1000;
    // 定义代币最大供应量：125万 YD（包含 18 位小数）
    uint256 public constant MAX_SUPPLY = 1250000;

    // 团队分配比例：20% = 25万 YD
    uint256 public teamAllocation;
    // 市场营销分配比例：10% = 12.5万 YD
    uint256 public marketingAllocation;
    // 社区分配比例：10% = 12.5万 YD
    uint256 public communityAllocation;
    // 剩余 60% = 75万 YD 用于公开销售

    // 标记初始代币分配是否已完成
    bool public initialDistributionDone;
    function decimals() public view virtual override returns (uint8) {
        return 0;
    }
    
    // 多签相关变量
    address[] public signers;               // 多签人列表
    uint256 public requiredSignatures;      // 需要的签名数量
    uint256 public withdrawalId;            // 提款请求ID计数器
    
    // 提款请求结构体
    struct WithdrawalRequest {
        uint256 amount;                     // 提款金额
        uint256 signatureCount;             // 已签名数量
        address recipient;                  // 接收者地址
        bool executed;                      // 是否已执行
        mapping(address => bool) signatures;// 签名记录
    }
    
    // 提款请求映射
    mapping(uint256 => WithdrawalRequest) public withdrawalRequests;
    
    // 新增事件
    event WithdrawalRequested(uint256 indexed withdrawalId, uint256 amount, address recipient);
    event WithdrawalSigned(uint256 indexed withdrawalId, address signer);
    event WithdrawalExecuted(uint256 indexed withdrawalId, uint256 amount, address recipient);
    
    // 原有事件定义
    event TokensPurchased(
        address indexed buyer,
        uint256 ethAmount,
        uint256 tokenAmount
    );
    event TokensSold(
        address indexed seller,
        uint256 tokenAmount,
        uint256 ethAmount
    );
    event InitialDistributionCompleted(
        address teamWallet,
        address marketingWallet,
        address communityWallet
    );

    // 构造函数：初始化代币名称为 "YiDeng Token"，符号为 "YD"
    constructor() ERC20("YiDeng Token", "YD") {
        // 计算各个分配额度
        teamAllocation = (MAX_SUPPLY * 20) / 100; // 20% 分配给团队
        marketingAllocation = (MAX_SUPPLY * 10) / 100; // 10% 分配给市场营销
        communityAllocation = (MAX_SUPPLY * 10) / 100; // 10% 分配给社区
        
        // 初始化多签，默认只有合约所有者
        signers.push(msg.sender);
        requiredSignatures = 1;
    }

    // 初始代币分配函数，只能由合约所有者调用
    function distributeInitialTokens(
        address teamWallet, // 团队钱包地址
        address marketingWallet, // 市场营销钱包地址
        address communityWallet // 社区钱包地址
    ) external onlyOwner {
        require(!initialDistributionDone, "Initial distribution already done");

        _mint(teamWallet, teamAllocation); // 铸造团队份额
        _mint(marketingWallet, marketingAllocation); // 铸造市场营销份额
        _mint(communityWallet, communityAllocation); // 铸造社区份额

        initialDistributionDone = true;
        emit InitialDistributionCompleted(
            teamWallet,
            marketingWallet,
            communityWallet
        );
    }

    // 使用 ETH 购买 YD 代币的函数
    function buyWithETH() external payable {
        require(msg.value > 0, "Must send ETH");

        uint256 tokenAmount = (msg.value * TOKENS_PER_ETH) / 1 ether;
        require(
            totalSupply() + tokenAmount <= MAX_SUPPLY,
            "Would exceed max supply"
        );

        _mint(msg.sender, tokenAmount);
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }

    /**
     * @notice 将YiDeng代币卖回换取ETH
     * @param tokenAmount 要卖出的代币数量
     */
    function sellTokens(uint256 tokenAmount) external {
        require(tokenAmount > 0, "Amount must be greater than 0");
        require(balanceOf(msg.sender) >= tokenAmount, "Insufficient balance");

        // 计算ETH数量
        uint256 ethAmount = tokenAmount / TOKENS_PER_ETH;
        require(
            address(this).balance >= ethAmount,
            "Insufficient ETH in contract"
        );

        // 先销毁代币
        _burn(msg.sender, tokenAmount);

        // 发送ETH给用户
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "ETH transfer failed");

        emit TokensSold(msg.sender, tokenAmount, ethAmount);
    }

    // 查询剩余可铸造的代币数量
    function remainingMintableSupply() public view returns (uint256) {
        return MAX_SUPPLY - totalSupply();
    }

    // 多签相关功能 ----------------------------------------
    
    // 检查是否是多签成员
    modifier onlyMultiSigner() {
        bool isMember = false;
        for (uint i = 0; i < signers.length; i++) {
            if (signers[i] == msg.sender) {
                isMember = true;
                break;
            }
        }
        require(isMember, "Not a sign member");
        _;
    }
    
    // 添加多签成员（只有合约所有者可调用）
    function addSigner(address newSigner) external onlyOwner {
        require(newSigner != address(0), "Invalid address");
        
        // 检查是否已经是多签成员
        for (uint i = 0; i < signers.length; i++) {
            require(signers[i] != newSigner, "Already a signer");
        }
        
        signers.push(newSigner);
    }
    
    // 移除多签成员（只有合约所有者可调用）
    function removeSigner(address signerToRemove) external onlyOwner {
        require(signers.length > requiredSignatures, "Cannot remove: too few signers");
        
        uint indexToRemove = signers.length;
        for (uint i = 0; i < signers.length; i++) {
            if (signers[i] == signerToRemove) {
                indexToRemove = i;
                break;
            }
        }
        
        require(indexToRemove < signers.length, "Signer not found");
        
        // 将最后一个元素移到要删除的位置，然后删除最后一个元素
        signers[indexToRemove] = signers[signers.length - 1];
        signers.pop();
    }
    
    // 修改所需签名数量（只有合约所有者可调用）
    function updateRequiredSignatures(uint256 newRequiredSignatures) external onlyOwner {
        require(newRequiredSignatures > 0, "Must require at least 1 signature");
        require(newRequiredSignatures <= signers.length, "Cannot require more signatures than signers");
        
        requiredSignatures = newRequiredSignatures;
    }
    
    // 发起提款请求（任何多签成员都可以发起）
    function requestWithdrawal(uint256 amount, address recipient) external onlyMultiSigner {
        require(amount > 0, "Amount must be greater than 0");
        require(recipient != address(0), "Invalid recipient address");
        require(address(this).balance >= amount, "Insufficient contract balance");
        
        uint256 requestId = withdrawalId;
        withdrawalId += 1;
        
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        request.amount = amount;
        request.recipient = recipient;
        request.executed = false;
        request.signatureCount = 1;  // 创建者自动签名
        request.signatures[msg.sender] = true;
        
        emit WithdrawalRequested(requestId, amount, recipient);
        emit WithdrawalSigned(requestId, msg.sender);
        
        // 如果只需要一个签名，则直接执行
        if (requiredSignatures == 1) {
            executeWithdrawal(requestId);
        }
    }
    
    // 签名提款请求
    function signWithdrawal(uint256 requestId) external onlyMultiSigner {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        
        require(!request.executed, "Withdrawal already executed");
        require(!request.signatures[msg.sender], "Already signed");
        
        request.signatures[msg.sender] = true;
        request.signatureCount += 1;
        
        emit WithdrawalSigned(requestId, msg.sender);
        
        // 检查是否达到所需签名数量
        if (request.signatureCount >= requiredSignatures) {
            executeWithdrawal(requestId);
        }
    }
    
    // 执行提款（内部函数）
    function executeWithdrawal(uint256 requestId) internal {
        WithdrawalRequest storage request = withdrawalRequests[requestId];
        
        require(!request.executed, "Withdrawal already executed");
        require(request.signatureCount >= requiredSignatures, "Not enough signatures");
        require(address(this).balance >= request.amount, "Insufficient contract balance");
        
        request.executed = true;
        
        (bool success, ) = request.recipient.call{value: request.amount}("");
        require(success, "ETH transfer failed");
        
        emit WithdrawalExecuted(requestId, request.amount, request.recipient);
    }
    
    // 获取多签成员数量
    function getSignerCount() external view returns (uint256) {
        return signers.length;
    }
    
    // 检查地址是否为多签成员
    function isSigner(address account) external view returns (bool) {
        for (uint i = 0; i < signers.length; i++) {
            if (signers[i] == account) {
                return true;
            }
        }
        return false;
    }
    
    // 检查是否已经签名特定提款请求
    function hasSignedWithdrawal(uint256 requestId, address signer) external view returns (bool) {
        return withdrawalRequests[requestId].signatures[signer];
    }

    // 允许合约接收ETH
    receive() external payable {}

    // 允许合约接收ETH（当调用不存在的函数时）
    fallback() external payable {}
}
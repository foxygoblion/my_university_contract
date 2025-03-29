// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// 导入所需的 OpenZeppelin 合约
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title CourseCertificate
 * @notice 易登课程证书NFT合约，用于发放课程完成证书
 */
contract CourseCertificate is ERC721, AccessControl {
    using Counters for Counters.Counter;
    using Strings for uint256;

    // NFT ID计数器
    Counters.Counter private _tokenIds;

    // 定义铸造者角色，只有拥有该角色才能铸造证书
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    // 证书数据结构
    struct CertificateData {
        string web2CourseId; // Web2平台的课程ID
        address student; // 学生地址
        uint256 timestamp; // 发放时间
        string metadataURI; // 元数据URI
    }

    // tokenId => 证书数据
    mapping(uint256 => CertificateData) public certificates;

    // 记录学生获得的证书：courseId => 学生地址 => tokenId数组
    mapping(string => mapping(address => uint256[])) public studentCertificates;

    // 事件
    event CertificateMinted(
        uint256 indexed tokenId,
        string web2CourseId,
        address indexed student
    );

    /**
     * @notice 构造函数，初始化NFT名称和符号
     */
    constructor() ERC721("YiDeng Course Certificate", "YDCC") {
        // 授予合约部署者管理员和铸造者权限
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /**
     * @notice 铸造新的课程证书
     * @param student 学生地址
     * @param web2CourseId 课程ID
     * @param metadataURI 元数据URI
     * @return uint256 新铸造的证书ID
     */
    function mintCertificate(
        address student,
        string memory web2CourseId,
        string memory metadataURI
    ) external onlyRole(MINTER_ROLE) returns (uint256) {
        require(student != address(0), "Invalid student address");

        // 生成新的tokenId
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        // 铸造NFT
        _safeMint(student, newTokenId);

        // 存储证书数据
        certificates[newTokenId] = CertificateData({
            web2CourseId: web2CourseId,
            student: student,
            timestamp: block.timestamp,
            metadataURI: metadataURI
        });

        // 记录学生的证书
        studentCertificates[web2CourseId][student].push(newTokenId);

        emit CertificateMinted(newTokenId, web2CourseId, student);
        return newTokenId;
    }

    /**
     * @notice 获取证书元数据URI
     * @param tokenId 证书ID
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_exists(tokenId), "Certificate does not exist");
        return certificates[tokenId].metadataURI;
    }

    /**
     * @notice 检查学生是否拥有某课程的证书
     * @param student 学生地址
     * @param web2CourseId 课程ID
     */
    function hasCertificate(
        address student,
        string memory web2CourseId
    ) public view returns (bool) {
        return studentCertificates[web2CourseId][student].length > 0;
    }

    /**
     * @notice 获取学生某课程的所有证书ID
     * @param student 学生地址
     * @param web2CourseId 课程ID
     */
    function getStudentCertificates(
        address student,
        string memory web2CourseId
    ) public view returns (uint256[] memory) {
        return studentCertificates[web2CourseId][student];
    }

    /**
     * @notice 实现 supportsInterface
     * @param interfaceId 接口ID
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./YiDengToken.sol";
import "./CourseCertificate.sol";

/**
 * @title CourseMarket
 * @notice 一灯教育课程市场合约
 */
contract CourseMarket is Ownable {
    // 合约实例
    YiDengToken public yiDengToken;
    CourseCertificate public certificate;

    // 课程结构体
    struct Course {
        string web2CourseId; // Web2平台的课程ID
        string name; // 课程名称
        uint256 price; // 课程价格(YD代币)
        bool isActive; // 课程是否可购买
        address creator; // 课程创建者地址
    }

    // 合约状态变量
    mapping(uint256 => Course) public courses; // courseId => Course
    mapping(string => uint256) public web2ToCourseId; // web2CourseId => courseId
    mapping(address => mapping(uint256 => bool)) public userCourses; // 用户购买记录
    uint256 public courseCount; // 课程总数

    // 事件
    event CoursePurchased(
        address indexed buyer,
        uint256 indexed courseId,
        string web2CourseId
    );
    event CourseCompleted(
        address indexed student,
        uint256 indexed courseId,
        uint256 certificateId
    );
    event CourseAdded(
        uint256 indexed courseId,
        string web2CourseId,
        string name
    );

    /**
     * @notice 构造函数
     * @param _tokenAddress YiDeng代币合约地址
     * @param _certificateAddress 证书NFT合约地址
     */
    constructor(address _tokenAddress, address _certificateAddress) {
        yiDengToken = YiDengToken(payable(_tokenAddress));
        certificate = CourseCertificate(_certificateAddress);
    }

    /**
     * @notice 添加新课程
     * @param web2CourseId Web2平台的课程ID
     * @param name 课程名称
     * @param price 课程价格(YD代币)
     */
    function addCourse(
        string calldata web2CourseId,
        string calldata name,
        uint256 price
    ) external onlyOwner {
        require(
            bytes(web2CourseId).length > 0,
            "Web2 course ID cannot be empty"
        );
        require(web2ToCourseId[web2CourseId] == 0, "Course already exists");

        courseCount++;

        courses[courseCount] = Course({
            web2CourseId: web2CourseId,
            name: name,
            price: price,
            isActive: true,
            creator: msg.sender
        });

        web2ToCourseId[web2CourseId] = courseCount;

        emit CourseAdded(courseCount, web2CourseId, name);
    }

    /**
     * @notice 购买课程
     * @param web2CourseId Web2平台的课程ID
     */
    function purchaseCourse(string calldata web2CourseId) external {
        uint256 courseId = web2ToCourseId[web2CourseId];
        require(courseId > 0, "Course does not exist");

        Course memory course = courses[courseId];
        require(course.isActive, "Course not active");
        require(!userCourses[msg.sender][courseId], "Already purchased");

        // 转移代币
        require(
            yiDengToken.transferFrom(msg.sender, course.creator, course.price),
            "Transfer failed"
        );

        userCourses[msg.sender][courseId] = true;
        emit CoursePurchased(msg.sender, courseId, web2CourseId);
    }


    /**
    * @notice 批量购买课程
    * @param web2CourseIds Web2平台的课程ID数组
    */
    function purchaseCourse(string[] calldata web2CourseIds) external {
        require(web2CourseIds.length > 0, "No courses specified");

        uint256 totalPrice = 0;
        mapping(address => uint256) memory creatorPayments; // 记录每个创建者的总付款
        
        // 第一步：验证所有课程并计算总价
        for (uint256 i = 0; i < web2CourseIds.length; i++) {
            uint256 courseId = web2ToCourseId[web2CourseIds[i]];
            require(courseId > 0, "Course does not exist");

            Course memory course = courses[courseId];
            require(course.isActive, "Course not active");
            require(!userCourses[msg.sender][courseId], "Already purchased");

            totalPrice += course.price;
            creatorPayments[course.creator] += course.price;
        }

        // 第二步：执行批量转账
        address[] memory creators = new address[](web2CourseIds.length);
        uint256[] memory amounts = new uint256[](web2CourseIds.length);
        uint256 creatorCount = 0;

        // 收集所有不同的创建者和他们的付款总额
        for (uint256 i = 0; i < web2CourseIds.length; i++) {
            uint256 courseId = web2ToCourseId[web2CourseIds[i]];
            Course memory course = courses[courseId];
            
            if (creatorPayments[course.creator] > 0) {
                creators[creatorCount] = course.creator;
                amounts[creatorCount] = creatorPayments[course.creator];
                creatorPayments[course.creator] = 0; // 防止重复添加
                creatorCount++;
            }
        }

        // 执行批量转账
        for (uint256 i = 0; i < creatorCount; i++) {
            require(
                yiDengToken.transferFrom(msg.sender, creators[i], amounts[i]),
                "Transfer failed"
            );
        }

        // 第三步：更新用户购买记录并触发事件
        for (uint256 i = 0; i < web2CourseIds.length; i++) {
            uint256 courseId = web2ToCourseId[web2CourseIds[i]];
            userCourses[msg.sender][courseId] = true;
            emit CoursePurchased(msg.sender, courseId, web2CourseIds[i]);
        }
    }
    
    /**
     * @notice 验证课程完成并发放证书
     * @param student 学生地址
     * @param web2CourseId Web2平台的课程ID
     */
    function verifyCourseCompletion(
        address student,
        string calldata web2CourseId
    ) external onlyOwner {
        uint256 courseId = web2ToCourseId[web2CourseId];
        require(courseId > 0, "Course does not exist");
        require(userCourses[student][courseId], "Course not purchased");
        require(
            !certificate.hasCertificate(student, web2CourseId),
            "Certificate already issued"
        );

        string memory metadataURI = generateCertificateURI(
            student,
            web2CourseId
        );
        uint256 tokenId = certificate.mintCertificate(
            student,
            web2CourseId,
            metadataURI
        );

        emit CourseCompleted(student, courseId, tokenId);
    }

    /**
     * @notice 批量验证课程完成
     * @param students 学生地址数组
     * @param web2CourseId Web2平台的课程ID
     */
    function batchVerifyCourseCompletion(
        address[] memory students,
        string calldata web2CourseId
    ) external onlyOwner {
        uint256 courseId = web2ToCourseId[web2CourseId];
        require(courseId > 0, "Course does not exist");

        for (uint256 i = 0; i < students.length; i++) {
            if (
                userCourses[students[i]][courseId] &&
                !certificate.hasCertificate(students[i], web2CourseId)
            ) {
                string memory metadataURI = generateCertificateURI(
                    students[i],
                    web2CourseId
                );
                uint256 tokenId = certificate.mintCertificate(
                    students[i],
                    web2CourseId,
                    metadataURI
                );

                emit CourseCompleted(students[i], courseId, tokenId);
            }
        }
    }

    /**
     * @notice 检查用户是否已购买课程
     * @param user 用户地址
     * @param web2CourseId Web2平台的课程ID
     */
    function hasCourse(
        address user,
        string calldata web2CourseId
    ) external view returns (bool) {
        uint256 courseId = web2ToCourseId[web2CourseId];
        require(courseId > 0, "Course does not exist");
        return userCourses[user][courseId];
    }

    /**
     * @notice 生成证书元数据URI
     * @param student 学生地址
     * @param web2CourseId Web2平台的课程ID
     */
    function generateCertificateURI(
        address student,
        string calldata web2CourseId
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "https://api.yideng.com/certificate/",
                    web2CourseId,
                    "/",
                    Strings.toHexString(student)
                )
            );
    }
}

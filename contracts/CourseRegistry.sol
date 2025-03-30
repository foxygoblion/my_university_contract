// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./CourseMarket.sol";

contract CourseRegistry is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant TEACHER_ROLE = keccak256("TEACHER_ROLE");

    CourseMarket public market;
    mapping(address => bool) public registeredTeachers;
    mapping(string => address) public courseToTeacher;

    event TeacherRegistered(address indexed teacher);
    event TeacherRemoved(address indexed teacher);
    event CourseRegistered(string indexed web2CourseId, address indexed teacher);

    constructor(address _market) {
        market = CourseMarket(_market);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function registerTeacher(address teacher) external onlyRole(ADMIN_ROLE) {
        require(!registeredTeachers[teacher], "Teacher already registered");
        registeredTeachers[teacher] = true;
        _grantRole(TEACHER_ROLE, teacher);
        emit TeacherRegistered(teacher);
    }

    function removeTeacher(address teacher) external onlyRole(ADMIN_ROLE) {
        require(registeredTeachers[teacher], "Teacher not registered");
        registeredTeachers[teacher] = false;
        _revokeRole(TEACHER_ROLE, teacher);
        emit TeacherRemoved(teacher);
    }

    function registerCourse(string calldata web2CourseId) external onlyRole(TEACHER_ROLE) {
        require(registeredTeachers[msg.sender], "Teacher not registered");
        require(courseToTeacher[web2CourseId] == address(0), "Course already registered");
        courseToTeacher[web2CourseId] = msg.sender;
        emit CourseRegistered(web2CourseId, msg.sender);
    }

    function isTeacherRegistered(address teacher) external view returns (bool) {
        return registeredTeachers[teacher];
    }

    function getCourseTeacher(string calldata web2CourseId) external view returns (address) {
        return courseToTeacher[web2CourseId];
    }
} 
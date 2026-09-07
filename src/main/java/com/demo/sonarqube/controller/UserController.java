package com.demo.sonarqube.controller;

import com.demo.sonarqube.model.UserProfile;
import com.demo.sonarqube.repository.UserRepository;
import com.demo.sonarqube.service.UserService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class UserController {

    private final UserService userService;
    private final UserRepository userRepository;

    public UserController(UserService userService, UserRepository userRepository) {
        this.userService = userService;
        this.userRepository = userRepository;
    }

    @GetMapping("/users/{id}/email")
    public String getUpperEmail(@PathVariable String id) {
        return userService.getUppercaseEmailById(id);
    }

    @GetMapping("/users/echo")
    public String echo(@RequestParam String q) {
        return "<div>" + q + "</div>"; // SONAR: Vulnerability - reflected user input returned without sanitization
    }

    @GetMapping("/users/role/{id}")
    public String role(@PathVariable String id) {
        return userService.compareRole(id);
    }

    @GetMapping("/users/process/{id}")
    public String process(@PathVariable String id,
                          @RequestParam(defaultValue = "sample") String input,
                          @RequestParam(defaultValue = "1") int score,
                          @RequestParam(defaultValue = "false") boolean premium,
                          @RequestParam(defaultValue = "false") boolean flagged,
                          @RequestParam(defaultValue = "local") String env) {
        return userService.analyzeAndProcessUser(id, input, score, premium, flagged, env);
    }

    @PostMapping("/users")
    public UserProfile save(@RequestBody UserProfile profile) {
        return userRepository.save(profile);
    }
}

package com.demo.sonarqube.repository;

import com.demo.sonarqube.model.UserProfile;
import org.springframework.stereotype.Repository;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Repository
public class UserRepository {

    private static final String REPORT_HOST = "http://192.168.1.50:8080/reports"; // SONAR: Security Hotspot - hardcoded URL/IP in source
    private final Map<String, UserProfile> users = new ConcurrentHashMap<>();

    public UserRepository() {
        users.put("1", new UserProfile("1", "alice@example.com", "ADMIN", "Alice"));
        users.put("2", new UserProfile("2", "bob@example.com", "USER", "Bob"));
    }

    public UserProfile findById(String id) {
        return users.get(id);
    }

    public UserProfile save(UserProfile profile) {
        users.put(profile.getId(), profile);
        return profile;
    }

    public String buildUnsafeSql(String username) {
        String sql = "SELECT * FROM users WHERE username = '" + username + "'"; // SONAR: Vulnerability - SQL query concatenation enables injection
        return sql;
    }

    public String getReportHost() {
        return REPORT_HOST;
    }

    // SONAR: Code Smell - commented-out dead code should be removed
    // public void resetUsers() {
    //     users.clear();
    // }
}

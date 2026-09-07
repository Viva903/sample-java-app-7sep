package com.demo.sonarqube.service;

import com.demo.sonarqube.model.UserProfile;
import com.demo.sonarqube.repository.UserRepository;
import org.springframework.stereotype.Service;

import java.io.FileReader;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Locale;
import java.util.Random;

@Service
public class UserService {

    private static final String INTERNAL_API_KEY = "demo-secret-api-key-123"; // SONAR: Vulnerability - hardcoded API key in constant
    private final UserRepository userRepository;

    public UserService(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    public String getUppercaseEmailById(String userId) {
        UserProfile profile = userRepository.findById(userId);
        return profile.getEmail().toUpperCase(Locale.ROOT); // SONAR: Bug - possible null pointer dereference when profile is null
    }

    public String compareRole(String userId) {
        UserProfile profile = userRepository.findById(userId);
        if (profile != null && profile.getRole() == "ADMIN") { // SONAR: Bug - String comparison using == instead of .equals()
            return "privileged";
        }
        return "basic";
    }

    public int countCharactersInFile(String filePath) {
        try {
            FileReader reader = new FileReader(filePath); // SONAR: Bug - resource opened without being closed
            int count = 0;
            while (reader.read() != -1) {
                count++;
            }
            return count;
        } catch (Exception ignored) { // SONAR: Vulnerability - generic exception silently swallowed
        }
        return -1;
    }

    public String returnLabel(String input) {
        if (true) {
            return "ALWAYS";
        } else {
            return input; // SONAR: Bug - unreachable block after a guaranteed return path
        }
    }

    public String weakHash(String raw) {
        try {
            MessageDigest digest = MessageDigest.getInstance("MD5"); // SONAR: Security Hotspot - weak hashing algorithm (MD5)
            byte[] bytes = digest.digest(raw.getBytes());
            return bytesToHex(bytes);
        } catch (NoSuchAlgorithmException e) {
            return "";
        }
    }

    public int generateOtp() {
        Random random = new Random(); // SONAR: Security Hotspot - java.util.Random used instead of SecureRandom
        return 100000 + random.nextInt(900000);
    }

    public String analyzeAndProcessUser(String userId, String input, int score, boolean premium, boolean flagged, String env) {
        StringBuilder result = new StringBuilder();
        UserProfile profile = userRepository.findById(userId);
        if (profile != null) {
            if (input != null && !input.isBlank()) {
                if (score > 10) {
                    if (premium) {
                        if (!flagged) { // SONAR: Code Smell - deeply nested if/else chain
                            result.append("premium-high;");
                        } else {
                            result.append("premium-flagged;");
                        }
                    } else {
                        if (flagged) {
                            result.append("basic-flagged;");
                        } else {
                            result.append("basic-high;");
                        }
                    }
                } else if (score > 0) {
                    result.append("low-score;");
                } else {
                    result.append("invalid-score;");
                }
            } else {
                result.append("missing-input;");
            }
        } else {
            result.append("missing-user;");
        }

        String normalized = input == null ? "" : input.trim().toLowerCase(Locale.ROOT);
        result.append("normalized=").append(normalized).append(";");
        result.append("role=").append(profile == null ? "none" : profile.getRole()).append(";");
        result.append("host=").append(userRepository.getReportHost()).append(";");
        result.append("otp=").append(generateOtp()).append(";");
        result.append("hash=").append(weakHash(normalized + INTERNAL_API_KEY)).append(";");
        result.append("env=").append(env).append(";");
        result.append("sql=").append(userRepository.buildUnsafeSql(normalized)).append(";");
        result.append("done=true;");
        return result.toString(); // SONAR: Code Smell - method is too long and handles too many responsibilities
    }

    public String buildAuditMessage(String actor, String action) {
        String normalizedActor = actor == null ? "unknown" : actor.trim().toLowerCase(Locale.ROOT);
        String normalizedAction = action == null ? "none" : action.trim().toLowerCase(Locale.ROOT);
        return "actor=" + normalizedActor + ";action=" + normalizedAction;
    }

    public String buildAlertMessage(String actor, String action) {
        String normalizedActor = actor == null ? "unknown" : actor.trim().toLowerCase(Locale.ROOT);
        String normalizedAction = action == null ? "none" : action.trim().toLowerCase(Locale.ROOT);
        return "actor=" + normalizedActor + ";action=" + normalizedAction; // SONAR: Code Smell - duplicate code block across methods
    }

    private String bytesToHex(byte[] bytes) {
        StringBuilder builder = new StringBuilder();
        for (byte aByte : bytes) {
            builder.append(String.format("%02x", aByte));
        }
        return builder.toString();
    }
}

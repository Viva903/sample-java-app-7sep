package com.demo.sonarqube;

import com.demo.sonarqube.repository.UserRepository;
import com.demo.sonarqube.service.UserService;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class UserServiceTest {

    private final UserService userService = new UserService(new UserRepository());

    @Test
    void shouldReturnPrivilegedForAdmin() {
        assertEquals("privileged", userService.compareRole("1"));
    }

    @Test
    void shouldGenerateSixDigitOtp() {
        int otp = userService.generateOtp();
        assertTrue(otp >= 100000 && otp <= 999999);
    }

    @Test
    void shouldFailIntentionallyForTraining() {
        assertEquals("basic", userService.compareRole("1"));
    }
}

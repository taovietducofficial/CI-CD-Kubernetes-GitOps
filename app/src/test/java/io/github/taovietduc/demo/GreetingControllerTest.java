package io.github.taovietduc.demo;

import org.junit.jupiter.api.Nested;
import org.junit.jupiter.api.Test;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.context.annotation.Import;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.assertj.MockMvcTester;

import static org.assertj.core.api.Assertions.assertThat;

@WebMvcTest(GreetingController.class)
@Import(GreetingService.class)
class GreetingControllerTest {

	@Autowired
	MockMvcTester mvc;

	@Test
	void greetsTheWorldByDefault() {
		assertThat(mvc.get().uri("/api/v1/greetings"))
			.hasStatusOk()
			.bodyJson().extractingPath("$.message").isEqualTo("Hello, world!");
	}

	@Test
	void greetsByName() {
		assertThat(mvc.get().uri("/api/v1/greetings").param("name", "  Duc "))
			.hasStatusOk()
			.bodyJson().extractingPath("$.message").isEqualTo("Hello, Duc!");
	}

	@Test
	void rejectsOverlongNameWithProblemDetail() {
		assertThat(mvc.get().uri("/api/v1/greetings").param("name", "x".repeat(51)))
			.hasStatus(HttpStatus.BAD_REQUEST)
			.hasContentTypeCompatibleWith(MediaType.APPLICATION_PROBLEM_JSON)
			.bodyJson().extractingPath("$.status").isEqualTo(400);
	}

	@Nested
	@TestPropertySource(properties = "app.chaos.error-rate=1")
	class WhenChaosIsOn {

		@Test
		void failsEveryRequest() {
			assertThat(mvc.get().uri("/api/v1/greetings")).hasStatus(HttpStatus.INTERNAL_SERVER_ERROR);
		}

	}

}

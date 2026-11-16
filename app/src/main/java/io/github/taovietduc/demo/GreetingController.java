package io.github.taovietduc.demo;

import java.util.concurrent.ThreadLocalRandom;

import jakarta.validation.constraints.Size;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/v1/greetings")
class GreetingController {

	private final GreetingService greetings;

	private final double chaosErrorRate;

	GreetingController(GreetingService greetings, @Value("${app.chaos.error-rate:0}") double chaosErrorRate) {
		this.greetings = greetings;
		this.chaosErrorRate = chaosErrorRate;
	}

	@GetMapping
	GreetingService.Greeting greet(@RequestParam(required = false) @Size(max = 50) String name) {
		if (chaosErrorRate > 0 && ThreadLocalRandom.current().nextDouble() < chaosErrorRate) {
			throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "chaos: injected failure");
		}
		return greetings.greet(name);
	}

}

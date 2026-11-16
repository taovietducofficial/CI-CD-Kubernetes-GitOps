package io.github.taovietduc.demo;

import org.springframework.stereotype.Service;

@Service
public class GreetingService {

	public Greeting greet(String name) {
		String who = (name == null || name.isBlank()) ? "world" : name.strip();
		return new Greeting("Hello, " + who + "!");
	}

	public record Greeting(String message) {
	}

}

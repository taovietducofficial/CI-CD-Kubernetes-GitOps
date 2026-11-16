package io.github.taovietduc.demo;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

import org.junit.jupiter.api.Test;

import org.springframework.boot.micrometer.metrics.test.autoconfigure.AutoConfigureMetrics;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.SpringBootTest.WebEnvironment;
import org.springframework.boot.test.web.server.LocalManagementPort;
import org.springframework.boot.test.web.server.LocalServerPort;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * Boots the real server and checks the contract Kubernetes depends on:
 * probes on the traffic port, metrics only on the management port.
 */
@SpringBootTest(webEnvironment = WebEnvironment.RANDOM_PORT, properties = "management.server.port=0")
@AutoConfigureMetrics // metrics export is off in tests by default
class DemoApplicationTests {

	private final HttpClient http = HttpClient.newHttpClient();

	@LocalServerPort
	int port;

	@LocalManagementPort
	int managementPort;

	@Test
	void probesAreServedOnTheTrafficPort() throws Exception {
		assertThat(get(port, "/livez").statusCode()).isEqualTo(200);
		assertThat(get(port, "/readyz").statusCode()).isEqualTo(200);
	}

	@Test
	void prometheusMetricsAreOnlyOnTheManagementPort() throws Exception {
		get(port, "/api/v1/greetings");

		HttpResponse<String> metrics = get(managementPort, "/actuator/prometheus");
		assertThat(metrics.statusCode()).isEqualTo(200);
		assertThat(metrics.body()).contains("http_server_requests_seconds_count");

		assertThat(get(port, "/actuator/prometheus").statusCode()).isEqualTo(404);
	}

	private HttpResponse<String> get(int port, String path) throws Exception {
		HttpRequest request = HttpRequest.newBuilder(URI.create("http://localhost:" + port + path)).build();
		return http.send(request, HttpResponse.BodyHandlers.ofString());
	}

}

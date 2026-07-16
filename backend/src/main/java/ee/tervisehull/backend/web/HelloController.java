package ee.tervisehull.backend.web;

import java.time.Instant;
import java.util.Map;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class HelloController {

	@GetMapping("/hello")
	public Map<String, Object> hello() {
		return Map.of(
			"message", "Tere tervisehull backendist!",
			"timestamp", Instant.now().toString()
		);
	}
}

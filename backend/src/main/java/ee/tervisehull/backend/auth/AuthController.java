package ee.tervisehull.backend.auth;

import java.util.Map;
import java.util.Optional;

import ee.tervisehull.backend.user.User;
import ee.tervisehull.backend.user.UserRepository;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import jakarta.validation.Valid;

import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class AuthController {

	private static final String INVALID_CREDENTIALS_MESSAGE = "Invalid email or password";

	private final UserRepository userRepository;
	private final BCryptPasswordEncoder passwordEncoder = new BCryptPasswordEncoder();

	public AuthController(UserRepository userRepository) {
		this.userRepository = userRepository;
	}

	@PostMapping("/login")
	public ResponseEntity<?> login(@RequestBody LoginRequest loginRequest, HttpServletRequest request) {
		Optional<User> user = userRepository.findByEmail(loginRequest.email());

		if (user.isEmpty() || !passwordEncoder.matches(loginRequest.password(), user.get().getPasswordHash())) {
			return ResponseEntity.status(401).body(Map.of("message", INVALID_CREDENTIALS_MESSAGE));
		}

		HttpSession session = request.getSession(true);
		session.setAttribute("userId", user.get().getId());

		return ResponseEntity.ok(new LoginResponse(user.get().getEmail()));
	}

	@PostMapping("/register")
	public ResponseEntity<?> register(@Valid @RequestBody RegisterRequest registerRequest, HttpServletRequest request) {
		if (userRepository.findByEmail(registerRequest.email()).isPresent()) {
			return ResponseEntity.status(409).body(Map.of("message", "Email already registered"));
		}

		User user = userRepository.save(
			new User(registerRequest.email(), passwordEncoder.encode(registerRequest.password())));

		HttpSession session = request.getSession(true);
		session.setAttribute("userId", user.getId());

		return ResponseEntity.ok(new LoginResponse(user.getEmail()));
	}

	@PostMapping("/logout")
	public ResponseEntity<Void> logout(HttpServletRequest request) {
		HttpSession session = request.getSession(false);
		if (session != null) {
			session.invalidate();
		}
		return ResponseEntity.ok().build();
	}

	@GetMapping("/me")
	public ResponseEntity<?> me(HttpServletRequest request) {
		HttpSession session = request.getSession(false);
		Object userId = session != null ? session.getAttribute("userId") : null;

		if (!(userId instanceof Long id)) {
			return ResponseEntity.status(401).body(Map.of("message", "Not logged in"));
		}

		return userRepository.findById(id)
			.<ResponseEntity<?>>map(user -> ResponseEntity.ok(new LoginResponse(user.getEmail())))
			.orElseGet(() -> ResponseEntity.status(401).body(Map.of("message", "Not logged in")));
	}
}

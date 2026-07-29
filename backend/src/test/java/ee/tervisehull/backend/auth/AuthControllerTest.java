package ee.tervisehull.backend.auth;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpSession;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class AuthControllerTest {

	@Autowired
	private MockMvc mockMvc;

	@Test
	void loginWithValidCredentialsCreatesSession() throws Exception {
		// MockMvc doesn't simulate the Set-Cookie header a real servlet container
		// writes for JSESSIONID, so we assert on session creation directly instead.
		MvcResult result = mockMvc.perform(post("/api/login")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"test@tervisehull.ee\",\"password\":\"DevPassword123!\"}"))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"email\":\"test@tervisehull.ee\"}"))
			.andReturn();

		assertNotNull(result.getRequest().getSession(false));
	}

	@Test
	void loginWithWrongPasswordReturns401() throws Exception {
		mockMvc.perform(post("/api/login")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"test@tervisehull.ee\",\"password\":\"wrong-password\"}"))
			.andExpect(status().isUnauthorized())
			.andExpect(content().json("{\"message\":\"Invalid email or password\"}"));
	}

	@Test
	void loginWithUnknownEmailReturns401WithSameMessage() throws Exception {
		mockMvc.perform(post("/api/login")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"nobody@tervisehull.ee\",\"password\":\"whatever\"}"))
			.andExpect(status().isUnauthorized())
			.andExpect(content().json("{\"message\":\"Invalid email or password\"}"));
	}

	@Test
	void logoutReturnsOk() throws Exception {
		mockMvc.perform(post("/api/logout"))
			.andExpect(status().isOk());
	}

	@Test
	void registeringNewEmailCreatesSession() throws Exception {
		MvcResult result = mockMvc.perform(post("/api/register")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"newuser@tervisehull.ee\",\"password\":\"SomePassword123\"}"))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"email\":\"newuser@tervisehull.ee\"}"))
			.andReturn();

		assertNotNull(result.getRequest().getSession(false));
	}

	@Test
	void registeringExistingEmailReturns409() throws Exception {
		mockMvc.perform(post("/api/register")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"test@tervisehull.ee\",\"password\":\"SomePassword123\"}"))
			.andExpect(status().isConflict())
			.andExpect(content().json("{\"message\":\"Email already registered\"}"));
	}

	@Test
	void registeringWithShortPasswordReturns400() throws Exception {
		mockMvc.perform(post("/api/register")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"shortpw@tervisehull.ee\",\"password\":\"short\"}"))
			.andExpect(status().isBadRequest());
	}

	@Test
	void meWithoutSessionReturns401() throws Exception {
		mockMvc.perform(get("/api/me"))
			.andExpect(status().isUnauthorized());
	}

	@Test
	void meAfterLoginReturnsEmail() throws Exception {
		MockHttpSession session = new MockHttpSession();

		mockMvc.perform(post("/api/login")
				.contentType(MediaType.APPLICATION_JSON)
				.content("{\"email\":\"test@tervisehull.ee\",\"password\":\"DevPassword123!\"}")
				.session(session))
			.andExpect(status().isOk());

		mockMvc.perform(get("/api/me").session(session))
			.andExpect(status().isOk())
			.andExpect(content().json("{\"email\":\"test@tervisehull.ee\"}"));
	}
}

package ee.tervisehull.backend.user;

import java.util.Optional;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.transaction.annotation.Transactional;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

// Full @SpringBootTest, not @DataJpaTest: the slice test excludes our own
// @Configuration beans (JpaAuditingConfig), so auditing wouldn't fire.
@SpringBootTest
@Transactional
class UserRepositoryTest {

	@Autowired
	private UserRepository userRepository;

	@Test
	void savingUserPopulatesAuditTimestamps() {
		User user = new User("audit-test@tervisehull.ee", "hash");

		User saved = userRepository.saveAndFlush(user);

		assertNotNull(saved.getId());
		assertNotNull(saved.getCreatedAt());
		assertNotNull(saved.getUpdatedAt());
	}

	@Test
	void findByEmailReturnsSeededTestUser() {
		Optional<User> found = userRepository.findByEmail("test@tervisehull.ee");

		assertTrue(found.isPresent());
	}
}

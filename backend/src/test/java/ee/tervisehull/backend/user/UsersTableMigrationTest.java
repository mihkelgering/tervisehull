package ee.tervisehull.backend.user;

import javax.sql.DataSource;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;

import static org.junit.jupiter.api.Assertions.assertEquals;

@SpringBootTest
class UsersTableMigrationTest {

	@Autowired
	private DataSource dataSource;

	@Test
	void usersTableExistsWithAuditColumnsAndSeedRow() {
		JdbcTemplate jdbcTemplate = new JdbcTemplate(dataSource);

		Integer seededCount = jdbcTemplate.queryForObject(
			"SELECT count(*) FROM users WHERE email = ?",
			Integer.class,
			"test@tervisehull.ee");

		assertEquals(1, seededCount);

		// Confirms the audit columns exist (throws if any column is missing).
		jdbcTemplate.queryForObject(
			"SELECT created_at, created_by, updated_at, updated_by FROM users WHERE email = ? LIMIT 1",
			(rs, rowNum) -> null,
			"test@tervisehull.ee");
	}
}

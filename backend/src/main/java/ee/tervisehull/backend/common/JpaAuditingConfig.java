package ee.tervisehull.backend.common;

import java.util.Optional;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.domain.AuditorAware;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

@Configuration
@EnableJpaAuditing(auditorAwareRef = "auditorAware")
public class JpaAuditingConfig {

	@Bean
	public AuditorAware<Long> auditorAware(CurrentUserHolder currentUserHolder) {
		return () -> Optional.ofNullable(currentUserHolder.getUserId());
	}
}

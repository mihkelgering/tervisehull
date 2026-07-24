package ee.tervisehull.backend.common;

import java.io.IOException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

@Component
public class CurrentUserFilter extends OncePerRequestFilter {

	private final CurrentUserHolder currentUserHolder;

	public CurrentUserFilter(CurrentUserHolder currentUserHolder) {
		this.currentUserHolder = currentUserHolder;
	}

	@Override
	protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
			throws ServletException, IOException {
		HttpSession session = request.getSession(false);
		if (session != null && session.getAttribute("userId") instanceof Long userId) {
			currentUserHolder.setUserId(userId);
		}
		filterChain.doFilter(request, response);
	}
}

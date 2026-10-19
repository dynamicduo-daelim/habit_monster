package kr.habitmonster.config;

import java.io.IOException;
import java.util.Optional;
import java.util.Set;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.common.ErrorResponses;
import kr.habitmonster.identity.User;
import kr.habitmonster.identity.UserRepository;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 토큰 검사를 통과한 요청의 사용자를 DB에서 한 번 더 본다.
 * <ul>
 * <li>탈퇴했거나 없는 사용자 → 401 {@code INVALID_TOKEN}. access 토큰(JWT)은 서버에 저장하지 않아 만료 전까지 스스로는 못 막으므로,
 * 여기서 막는다 (결정 A1).</li>
 * <li>온보딩 전 사용자가 온보딩 밖의 요청 → 403 {@code ONBOARDING_REQUIRED}.</li>
 * </ul>
 * 요청마다 기본 키 조회 1번이 늘어나는 대신, 탈퇴 즉시 모든 요청이 막힌다.
 */
public class UserGateFilter extends OncePerRequestFilter {

	/** 온보딩 전에도 부를 수 있는 경로 (컨텍스트 경로 {@code /api/v1} 뒤). */
	static final Set<String> BEFORE_ONBOARDING = Set.of(
		"/categories", "/measure-types", "/onboarding", // 온보딩 화면
		"/me", "/me/device-token"); // 계정 표시 · 탈퇴 · 푸시 토큰

	private final UserRepository users;

	public UserGateFilter(UserRepository users) {
		this.users = users;
	}

	@Override
	protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
			throws ServletException, IOException {
		Authentication auth = SecurityContextHolder.getContext().getAuthentication();
		if (auth instanceof JwtAuthenticationToken token) {
			Optional<User> user = users.findById(Long.valueOf(token.getName()));
			if (user.isEmpty() || user.get().isWithdrawn()) {
				SecurityContextHolder.clearContext();
				ErrorResponses.write(res, ErrorCode.INVALID_TOKEN);
				return;
			}
			if (!user.get().isOnboardingDone() && !BEFORE_ONBOARDING.contains(path(req))) {
				ErrorResponses.write(res, ErrorCode.ONBOARDING_REQUIRED);
				return;
			}
		}
		chain.doFilter(req, res);
	}

	private static String path(HttpServletRequest req) {
		return req.getRequestURI().substring(req.getContextPath().length());
	}
}

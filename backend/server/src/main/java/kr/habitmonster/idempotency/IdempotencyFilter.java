package kr.habitmonster.idempotency;

import java.io.BufferedReader;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.HexFormat;
import java.util.UUID;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ReadListener;
import jakarta.servlet.ServletException;
import jakarta.servlet.ServletInputStream;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletRequestWrapper;
import jakarta.servlet.http.HttpServletResponse;

import kr.habitmonster.common.ErrorCode;
import kr.habitmonster.common.ErrorResponses;
import kr.habitmonster.idempotency.IdempotencyStore.KeyBusyException;
import kr.habitmonster.idempotency.IdempotencyStore.Saved;
import kr.habitmonster.idempotency.IdempotencyStore.Scope;

import org.springframework.beans.factory.ObjectProvider;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.MediaType;
import org.springframework.http.server.RequestPath;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.method.HandlerMethod;
import org.springframework.web.servlet.HandlerExecutionChain;
import org.springframework.web.servlet.HandlerMapping;
import org.springframework.web.util.ContentCachingResponseWrapper;
import org.springframework.web.util.ServletRequestPathUtils;

/**
 * 중복 요청 방지 키 — {@link Idempotent}가 붙은 API에서만 동작한다. (Spring Security 다음에 실행 = 요청 검사 순서 ③)
 *
 * <p>버튼을 누를 때 앱이 만든 UUID를 {@code Idempotency-Key} 헤더로 보내고, 응답을 못 받아 다시 보낼 때는 같은 값을 쓴다.
 * 서버는 키별로 첫 결과를 저장해 두었다가 그대로 돌려주므로, 네트워크가 끊겨 다시 보내도 골드 · 아이템이 두 번 처리되지 않는다.
 *
 * <ul>
 * <li>같은 키 · 같은 본문, 결과 있음 → 저장된 결과(상태 코드 포함) 그대로</li>
 * <li>같은 키 · 다른 본문 → 422 {@code IDEMPOTENCY_KEY_REUSED}</li>
 * <li>같은 키가 처리 중 → 409 {@code REQUEST_IN_PROGRESS}</li>
 * </ul>
 *
 * <p>처리 방식 (결정 A2) — 요청 전체를 트랜잭션 하나로 감싼다:
 * <ol>
 * <li>키 행을 {@code FOR UPDATE NOWAIT}로 잠근다. 잠겨 있으면 다른 요청이 처리 중이다.
 * 서버가 처리 중에 죽어도 DB가 잠금을 풀어 주므로 "처리 중"이 영원히 남지 않는다.</li>
 * <li>2xx → 결과를 같은 트랜잭션에 저장하고 비즈니스 변경과 함께 커밋 (둘 중 하나만 남는 일이 없음).</li>
 * <li>4xx → 비즈니스 변경은 되돌리고, 결과만 따로 저장 (다시 보내도 같은 오류).</li>
 * <li>5xx · 예외 → 모두 되돌리고 저장하지 않음 (같은 키로 다시 시도 가능).</li>
 * </ol>
 */
@Component
public class IdempotencyFilter extends OncePerRequestFilter {

	public static final String HEADER = "Idempotency-Key";
	public static final String REPLAYED_HEADER = "Idempotent-Replayed";

	private final ObjectProvider<HandlerMapping> handlerMapping;
	private final IdempotencyStore store;
	private final TransactionTemplate tx;

	IdempotencyFilter(@Qualifier("requestMappingHandlerMapping") ObjectProvider<HandlerMapping> handlerMapping,
			IdempotencyStore store, PlatformTransactionManager txm) {
		this.handlerMapping = handlerMapping;
		this.store = store;
		this.tx = new TransactionTemplate(txm);
	}

	private sealed interface Outcome {
	}

	private record Replay(Saved saved) implements Outcome {
	}

	private record KeyReused() implements Outcome {
	}

	/** 처음 처리했다. {@code storeLater}면 4xx라서 트랜잭션을 되돌린 뒤 결과만 저장한다. */
	private record Executed(boolean storeLater) implements Outcome {
	}

	@Override
	protected void doFilterInternal(HttpServletRequest req, HttpServletResponse res, FilterChain chain)
			throws ServletException, IOException {
		Authentication auth = SecurityContextHolder.getContext().getAuthentication();
		if (!(auth instanceof JwtAuthenticationToken) || !isIdempotent(req)) {
			chain.doFilter(req, res);
			return;
		}
		UUID key = parseKey(req.getHeader(HEADER));
		if (key == null) {
			ErrorResponses.write(res, ErrorCode.INVALID_REQUEST);
			return;
		}
		CachedBodyRequest request = new CachedBodyRequest(req);
		String path = req.getRequestURI(); // 전체 경로 (/api/v1/…) — DB 주석과 같게
		Scope scope = new Scope(Long.parseLong(auth.getName()), req.getMethod(), path, key);
		String hash = sha256(req.getQueryString(), request.body);

		store.prepare(scope, hash);
		ContentCachingResponseWrapper response = new ContentCachingResponseWrapper(res);
		Outcome outcome;
		try {
			outcome = tx.execute(status -> {
				Saved saved = store.lock(scope).orElseThrow();
				if (!saved.requestHash().equals(hash)) {
					return new KeyReused();
				}
				if (saved.completed()) {
					return new Replay(saved);
				}
				runChain(chain, request, response);
				int code = response.getStatus();
				if (code < 300) {
					store.complete(scope, code, text(response));
					return new Executed(false);
				}
				status.setRollbackOnly();
				return new Executed(code < 500);
			});
		}
		catch (KeyBusyException busy) {
			ErrorResponses.write(res, ErrorCode.REQUEST_IN_PROGRESS);
			return;
		}
		catch (ChainFailure e) {
			throw e.unwrap();
		}

		switch (outcome) {
			case Replay r -> replay(res, r.saved());
			case KeyReused k -> ErrorResponses.write(res, ErrorCode.IDEMPOTENCY_KEY_REUSED);
			case Executed e -> {
				if (e.storeLater()) {
					store.completeInNewTx(scope, response.getStatus(), text(response));
				}
				response.copyBodyToResponse();
			}
		}
	}

	/** 이 요청을 처리할 컨트롤러 메서드에 {@link Idempotent}가 있는지. */
	private boolean isIdempotent(HttpServletRequest req) {
		HandlerMapping mapping = handlerMapping.getIfAvailable();
		if (mapping == null) {
			return false;
		}
		RequestPath previous = ServletRequestPathUtils.hasParsedRequestPath(req)
				? ServletRequestPathUtils.getParsedRequestPath(req) : null;
		ServletRequestPathUtils.parseAndCache(req);
		try {
			HandlerExecutionChain handler = mapping.getHandler(req);
			return handler != null && handler.getHandler() instanceof HandlerMethod m && m.hasMethodAnnotation(Idempotent.class);
		}
		catch (Exception noMatch) { // 405 등은 DispatcherServlet이 처리
			return false;
		}
		finally {
			if (previous == null) {
				ServletRequestPathUtils.clearParsedRequestPath(req);
			}
			else {
				ServletRequestPathUtils.setParsedRequestPath(previous, req);
			}
		}
	}

	private static void replay(HttpServletResponse res, Saved saved) throws IOException {
		res.setStatus(saved.status());
		res.setHeader(REPLAYED_HEADER, "true");
		if (saved.body() != null && !saved.body().isEmpty()) {
			// 우리 API 응답은 모두 JSON (DB에도 JSONB로 저장 — 키 순서 · 공백은 바뀔 수 있지만 내용은 같다)
			res.setContentType(MediaType.APPLICATION_JSON_VALUE);
			res.setCharacterEncoding(StandardCharsets.UTF_8.name());
			res.getOutputStream().write(saved.body().getBytes(StandardCharsets.UTF_8));
		}
	}

	private static void runChain(FilterChain chain, HttpServletRequest req, HttpServletResponse res) {
		try {
			chain.doFilter(req, res);
		}
		catch (IOException | ServletException e) {
			throw new ChainFailure(e);
		}
	}

	private static UUID parseKey(String header) {
		if (header == null) {
			return null;
		}
		try {
			return UUID.fromString(header.trim());
		}
		catch (IllegalArgumentException e) {
			return null;
		}
	}

	private static String text(ContentCachingResponseWrapper res) {
		return new String(res.getContentAsByteArray(), StandardCharsets.UTF_8);
	}

	private static String sha256(String query, byte[] body) {
		try {
			MessageDigest md = MessageDigest.getInstance("SHA-256");
			md.update((query == null ? "" : query).getBytes(StandardCharsets.UTF_8));
			md.update((byte) '\n');
			md.update(body);
			return HexFormat.of().formatHex(md.digest());
		}
		catch (NoSuchAlgorithmException e) {
			throw new IllegalStateException(e);
		}
	}

	/** 트랜잭션 콜백 밖으로 checked 예외를 꺼내기 위한 포장. */
	private static final class ChainFailure extends RuntimeException {

		ChainFailure(Exception cause) {
			super(cause);
		}

		ServletException unwrap() throws IOException {
			if (getCause() instanceof IOException io) {
				throw io;
			}
			return (ServletException) getCause();
		}
	}

	/** 본문을 미리 읽어 둔 요청 — 해시를 계산한 뒤에도 컨트롤러가 본문을 다시 읽을 수 있게. */
	private static final class CachedBodyRequest extends HttpServletRequestWrapper {

		final byte[] body;

		CachedBodyRequest(HttpServletRequest req) throws IOException {
			super(req);
			this.body = req.getInputStream().readAllBytes();
		}

		@Override
		public ServletInputStream getInputStream() {
			ByteArrayInputStream in = new ByteArrayInputStream(body);
			return new ServletInputStream() {
				@Override
				public int read() {
					return in.read();
				}

				@Override
				public int read(byte[] b, int off, int len) {
					return in.read(b, off, len);
				}

				@Override
				public boolean isFinished() {
					return in.available() == 0;
				}

				@Override
				public boolean isReady() {
					return true;
				}

				@Override
				public void setReadListener(ReadListener listener) {
					throw new UnsupportedOperationException();
				}
			};
		}

		@Override
		public BufferedReader getReader() {
			String enc = getCharacterEncoding() == null ? StandardCharsets.UTF_8.name() : getCharacterEncoding();
			return new BufferedReader(new InputStreamReader(getInputStream(), Charset.forName(enc)));
		}
	}
}

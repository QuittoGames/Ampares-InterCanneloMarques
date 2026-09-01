package cannelo.marques.interdisciplinar.interdisciplinar.Services.Auth.Cookies;

import java.util.logging.Level;
import java.util.logging.Logger;

import org.springframework.stereotype.Service;

import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Service
public class CookieService {
    private static final Logger logger = Logger.getLogger(CookieService.class.getName());

    public void set(HttpServletResponse response, String user_id, int maxAge) {
        Cookie cookie = new Cookie("user_id", user_id);
        cookie.setHttpOnly(true);
        cookie.setPath("/");
        cookie.setMaxAge(maxAge);

        response.addCookie(cookie);
    }

    public void clear(HttpServletResponse response) {
        Cookie cookie = new Cookie("user_id", "");
        cookie.setHttpOnly(true);
        cookie.setPath("/");
        cookie.setMaxAge(0);

        response.addCookie(cookie);
    }

    public Cookie get(HttpServletRequest request,int id) {
        try {
            for(Cookie cookie:request.getCookies()){
                if (id == Integer.valueOf(cookie.getValue())){
                    return cookie;
                }
            }
            return null;
        } catch (Exception e) {
            logger.log(Level.SEVERE, "Erro ao processar cookie do usuário", e);
            return null;
        }
    }
}

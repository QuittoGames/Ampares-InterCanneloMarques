package cannelo.marques.interdisciplinar.interdisciplinar.Services.Auth;

import java.util.Objects;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Auth.Cookies.CookieService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.UserService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;
import jakarta.servlet.http.Cookie;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;


@Service
public class AuthService{
    private final CookieService cookieService;
    private final UserService userService;

    public AuthService(CookieService cookieService, UserService userService){
        this.cookieService = cookieService;
        this.userService = userService;
    }

    public void login(String idString, HttpServletRequest request, HttpServletResponse response) throws UserNotFoundException{
        Objects.requireNonNull(idString);
        Objects.requireNonNull(request);
        Objects.requireNonNull(response);

        int id = Integer.valueOf(idString);

        if (!userService.userExists(new User(Integer.valueOf(id)))){
            throw new UserNotFoundException("User not found with the provided ID");
        }

        Cookie cookie = cookieService.get(request, id);
        Objects.requireNonNull(cookie);

        cookieService.set(response, idString, 60 * 60 * 24 * 7);
    }
}

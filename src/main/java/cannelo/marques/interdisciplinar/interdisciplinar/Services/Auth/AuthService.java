package cannelo.marques.interdisciplinar.interdisciplinar.Services.Auth;

import java.util.Objects;
import java.util.Optional;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.User;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Auth.Cookies.CookieService;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.User.UserService;
import cannelo.marques.interdisciplinar.interdisciplinar.exceptions.UserNotFoundException;
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

    public void login(String idString, HttpServletRequest request, HttpServletResponse response) throws UserNotFoundException, NumberFormatException{
        Objects.requireNonNull(idString);
        Objects.requireNonNull(request);
        Objects.requireNonNull(response);

        int id;

        try {
            id = Integer.parseInt(idString);
        } catch (NumberFormatException exception) {
            NumberFormatException formattedException = new NumberFormatException(
                    "Invalid user ID: " + idString);
            formattedException.initCause(exception);
            throw formattedException;
        }

        if (!userService.userExists(new User(id))){
            throw new UserNotFoundException("User not found with the provided ID");
        }

        cookieService.set(response, idString, 60 * 60 * 24 * 7);
    }

    public void logout(HttpServletResponse response){
        Objects.requireNonNull(response);
        cookieService.clear(response);
    }

    public User register() throws UserNotFoundException {
        return userService.create().orElseThrow(() ->
                new UserNotFoundException("Unable to register user"));
}
}

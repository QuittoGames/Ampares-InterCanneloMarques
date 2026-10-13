package cannelo.marques.interdisciplinar.interdisciplinar.Services.Auth;

import java.util.Objects;

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

    /**
     * Autentica o usuário pelo id enviado pelo cliente.
     *
     * <p>Se o usuário ainda não existir, ele é <b>criado com o MESMO id
     * informado</b> — o id que o cliente conhece é sempre o id real no
     * banco. Em ambos os casos (novo ou existente) o cookie de sessão
     * {@code user_id} é definido.
     *
     * @param idString id do usuário (numérico, como texto)
     * @param request requisição atual (reservado para validações futuras)
     * @param response resposta na qual o cookie de sessão é setado
     * @throws NumberFormatException se {@code idString} não for numérico
     * @throws UserNotFoundException se a criação do usuário falhar
     */
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
            userService.create(id).orElseThrow(() ->
                    new UserNotFoundException("Unable to register user with the provided ID"));
        }

        cookieService.set(response, idString, 60 * 60 * 24 * 7);
    }

    public void logout(HttpServletResponse response){
        Objects.requireNonNull(response);
        cookieService.clear(response);
    }

    /**
     * Registra um usuário novo com id gerado pelo banco.
     *
     * <p>API de registro independente — o fluxo de login NÃO depende dela:
     * {@link #login(String, HttpServletRequest, HttpServletResponse)}
     * cria o usuário com o id do cliente quando necessário.
     *
     * @return o usuário criado
     * @throws UserNotFoundException se a criação falhar
     */
    public User register() throws UserNotFoundException {
        return userService.create().orElseThrow(() ->
                new UserNotFoundException("Unable to register user"));
}
}

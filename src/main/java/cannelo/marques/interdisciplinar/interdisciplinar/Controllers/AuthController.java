package cannelo.marques.interdisciplinar.interdisciplinar.Controllers;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import cannelo.marques.interdisciplinar.interdisciplinar.DTO.LoginDTO;
import cannelo.marques.interdisciplinar.interdisciplinar.Services.Auth.AuthService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;

@RestController
@RequestMapping("/auth")
@Tag(name = "Auth", description = "Endpoints de autenticação")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService){
        this.authService = authService;
    }

    @Operation(
        summary = "Autentica usuário por ID e define cookie de sessão",
        description = "Se o usuário ainda não existir, é criado com o MESMO id informado pelo cliente. "
                + "Em ambos os casos define o cookie HttpOnly user_id com TTL de 7 dias. "
                + "Resposta 200 com corpo vazio — o id usado é o que o cliente já conhece."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Login bem-sucedido (usuário criado, se necessário)"),
        @ApiResponse(responseCode = "400", description = "ID vazio ou inválido")
    })
    @PostMapping("/login")
    public ResponseEntity<Void> login(@RequestBody @Valid LoginDTO dto,
            HttpServletRequest request,
            HttpServletResponse response){
        authService.login(dto.id(), request, response);
        return ResponseEntity.ok().build();
    }

    @Operation(
        summary = "Limpa o cookie de sessão",
        description = "Remove o cookie HttpOnly user_id usado pela sessão do frontend."
    )
    @ApiResponse(responseCode = "200", description = "Sessão limpa com sucesso")
    @PostMapping("/logout")
    public ResponseEntity<Void> logout(HttpServletResponse response){
        authService.logout(response);
        return ResponseEntity.ok().build();
    }

}

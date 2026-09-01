package cannelo.marques.interdisciplinar.interdisciplinar.config;

import io.swagger.v3.oas.models.OpenAPI;
import io.swagger.v3.oas.models.info.Contact;
import io.swagger.v3.oas.models.info.Info;
import io.swagger.v3.oas.models.info.License;
import io.swagger.v3.oas.models.servers.Server;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import java.util.List;

@Configuration
public class OpenApiConfig {

    @Bean
    public OpenAPI customOpenAPI() {
        return new OpenAPI()
            .info(new Info()
                .title("Ampares-InterCanneloMarques API")
                .description("API REST para cálculo de métricas de consumo energético de produtos eletrodomésticos.")
                .version("0.0.1-SNAPSHOT")
                .contact(new Contact()
                    .name("Quitto")
                    .email("dev@local"))
                .license(new License()
                    .name("Projeto Escolar Interdisciplinar")))
            .servers(List.of(
                new Server().url("http://localhost:8080").description("Local")
            ));
    }
}

package cannelo.marques.interdisciplinar.interdisciplinar.exceptions;

public class UserNotFoundException extends RuntimeException {
    public UserNotFoundException(String message) {
        super(message);
    }
}

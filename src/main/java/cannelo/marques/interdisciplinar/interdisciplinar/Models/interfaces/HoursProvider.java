package cannelo.marques.interdisciplinar.interdisciplinar.Models.interfaces;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

import org.aspectj.lang.annotation.Aspect;

@Target(ElementType.METHOD)
@Retention(RetentionPolicy.RUNTIME)
@Aspect
public @interface HoursProvider {
}

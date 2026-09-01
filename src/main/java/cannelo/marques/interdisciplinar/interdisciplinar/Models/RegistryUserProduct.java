package cannelo.marques.interdisciplinar.interdisciplinar.Models;

import java.math.BigDecimal;
import java.util.UUID;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.interfaces.HoursProvider;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "registry_user_product")
public class RegistryUserProduct {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @ManyToOne
    @JoinColumn(name = "product_id", nullable = false)
    private Product product;

    private int quantity;

    @Column(name = "avg_active_hours")
    private BigDecimal avgActiveHours;

    @Column(name = "hours_standby")
    private BigDecimal hoursStandby;

    public RegistryUserProduct() {
    }

    public RegistryUserProduct(UUID id, User user, int quantity, BigDecimal avgActiveHours, BigDecimal hoursStandby, Product product) {
        this.id = id;
        this.user = user;
        this.quantity = quantity;
        this.avgActiveHours = avgActiveHours;
        this.hoursStandby = hoursStandby;
        this.product = product;
    }

    public UUID getId() {
        return id;
    }

    public User getUser() {
        return user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public Product getProduct() {
        return product;
    }

    public void setProduct(Product product) {
        this.product = product;
    }

    public int getQuantity() {
        return quantity;
    }

    public void setQuantity(int quantity) {
        this.quantity = quantity;
    }

    @HoursProvider
    public BigDecimal getAvgActiveHours() {
        return avgActiveHours;
    }

    public void setAvgActiveHours(BigDecimal avgActiveHours) {
        this.avgActiveHours = avgActiveHours;
    }

    @HoursProvider
    public BigDecimal getHoursStandby() {
        return hoursStandby;
    }

    public void setHoursStandby(BigDecimal hoursStandby) {
        this.hoursStandby = hoursStandby;
    }
}

package cannelo.marques.interdiciplinar.interdiciplinar.Models;

import java.math.BigDecimal;
import java.util.UUID;

import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "userproduct")
public class UserProduct {
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
    private BigDecimal avg_active_hours;
    private BigDecimal hours_standby;

    public UserProduct() {
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

    public BigDecimal getAvg_active_hours() {
        return avg_active_hours;
    }

    public void setAvg_active_hours(BigDecimal avg_active_hours) {
        this.avg_active_hours = avg_active_hours;
    }

    public BigDecimal getHours_standby() {
        return hours_standby;
    }

    public void setHours_standby(BigDecimal hours_standby) {
        this.hours_standby = hours_standby;
    }
}

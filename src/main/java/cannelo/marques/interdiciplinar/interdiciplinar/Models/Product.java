package cannelo.marques.interdiciplinar.interdiciplinar.Models;

import java.math.BigDecimal;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;

@Entity
public class Product {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "name", length = 150)
    private String name;

    private String brand;
    private String model;
    private String category;
    private BigDecimal avg_power_w;
    private BigDecimal annual_energy_kwh;

    public Product() {
    }

    public Product(UUID id) {
        this.id = id;
    }

    public Product(UUID id, String name, String brand, String model, String category,
                   BigDecimal avg_power_w, BigDecimal annual_energy_kwh) {
        this.id = id;
        this.name = name;
        this.brand = brand;
        this.model = model;
        this.category = category;
        this.avg_power_w = avg_power_w;
        this.annual_energy_kwh = annual_energy_kwh;
    }

    public UUID getId() {
        return id;
    }

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getBrand() {
        return brand;
    }

    public void setBrand(String brand) {
        this.brand = brand;
    }

    public String getModel() {
        return model;
    }

    public void setModel(String model) {
        this.model = model;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public BigDecimal getAvg_power_w() {
        return avg_power_w;
    }

    public void setAvg_power_w(BigDecimal avg_power_w) {
        this.avg_power_w = avg_power_w;
    }

    public BigDecimal getAnnual_energy_kwh() {
        return annual_energy_kwh;
    }

    public void setAnnual_energy_kwh(BigDecimal annual_energy_kwh) {
        this.annual_energy_kwh = annual_energy_kwh;
    }
}

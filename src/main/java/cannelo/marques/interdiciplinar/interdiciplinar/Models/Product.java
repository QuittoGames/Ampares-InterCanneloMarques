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
    private String subcategory;
    @Column(name = "avg_power_w")
    private BigDecimal avgPowerW;

    @Column(name = "annual_energy_kwh")
    private BigDecimal annualEnergyKwh;

    public Product() {
    }

    public Product(UUID id) {
        this.id = id;
    }

    public Product(UUID id, String name, String brand, String model, String category,
                   String subcategory, BigDecimal avgPowerW, BigDecimal annualEnergyKwh) {
        this.id = id;
        this.name = name;
        this.brand = brand;
        this.model = model;
        this.category = category;
        this.subcategory = subcategory;
        this.avgPowerW = avgPowerW;
        this.annualEnergyKwh = annualEnergyKwh;
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

    public String getSubcategory() {
        return subcategory;
    }

    public void setSubcategory(String subcategory) {
        this.subcategory = subcategory;
    }

    public BigDecimal getAvgPowerW() {
        return avgPowerW;
    }

    public void setAvgPowerW(BigDecimal avgPowerW) {
        this.avgPowerW = avgPowerW;
    }

    public BigDecimal getAnnualEnergyKwh() {
        return annualEnergyKwh;
    }

    public void setAnnualEnergyKwh(BigDecimal annualEnergyKwh) {
        this.annualEnergyKwh = annualEnergyKwh;
    }
}

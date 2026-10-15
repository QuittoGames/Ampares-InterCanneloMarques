package cannelo.marques.interdisciplinar.interdisciplinar.Models;

import java.math.BigDecimal;
import java.util.List;
import java.util.UUID;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Transient;

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

    /**
     * Potência média em modo standby (W) — atributo DISTINTO de
     * {@link #avgPowerW} (potência ATIVA). {@code null} = dado ausente /
     * não calculável; NUNCA deve ser substituída pela potência ativa nem
     * tratada como zero (decision_004 / SPEC §7).
     */
    @Column(name = "avg_idle_energy_for_hour")
    private BigDecimal avgIdleEnergyForHour;

    /**
     * Tensões distintas declaradas nas observações de fonte (V) — ex.:
     * [127, 220] quando o PBE declara modelos monovolt nas DUAS tensões
     * para o mesmo produto canônico. Campo de EXIBIÇÃO populado sob
     * demanda pelo {@code ProductVoltageService} ({@code @Transient},
     * não persistido — as tensões continuam morando em
     * {@code product_source_observation}). Lista vazia = nenhuma tensão
     * declarada. NUNCA inferir tensão ausente (units.js/collector).
     */
    @Transient
    private List<Integer> declaredVoltages;

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

    public BigDecimal getAvgIdleEnergyForHour() {
        return avgIdleEnergyForHour;
    }

    public void setAvgIdleEnergyForHour(BigDecimal avgIdleEnergyForHour) {
        this.avgIdleEnergyForHour = avgIdleEnergyForHour;
    }

    public List<Integer> getDeclaredVoltages() {
        return declaredVoltages;
    }

    public void setDeclaredVoltages(List<Integer> declaredVoltages) {
        this.declaredVoltages = declaredVoltages;
    }
}

package cannelo.marques.interdisciplinar.interdisciplinar.Models;

import java.util.List;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

import cannelo.marques.interdisciplinar.interdisciplinar.Models.RegistryUserProduct;

@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private int id;

    @Column(nullable =  true)
    private String name;

    @OneToMany(mappedBy = "user")
    private List<RegistryUserProduct> registryUserProducts;

    public User(){
    }

    public User(int id, String name){
        this.id = id;
        this.name = name;
    }

    public User(int id){
        this.id = id;
    }

    public int getId(){
        return id;
    }

    public String getName(){
        return name;
    }

    public void addRegistryUserProduct(RegistryUserProduct product){
        this.registryUserProducts.add(product);
    }

    public void removeRegistryUserProduct(RegistryUserProduct product){
        this.registryUserProducts.remove(this.registryUserProducts.indexOf(product.getId()));
    }

    @Override
    public boolean equals(Object obj){
        if (this == obj) return true;
        if (obj == null) return false;
        if (getClass() != obj.getClass()) return false;
        User other = (User) obj;
        if (id != other.id) return false;
        if (name == null){
            if (other.name != null) return false;
        } else if (!name.equals(other.name)) return false;
        return true;
    }

    @Override
    public String toString(){
        return "User [id=" + id + ", name=" + name + "]";
    }
}

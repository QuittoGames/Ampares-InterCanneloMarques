package cannelo.marques.interdiciplinar.interdiciplinar.Services;

import org.springframework.stereotype.Service;

import cannelo.marques.interdiciplinar.interdiciplinar.Repository.ProductRepository;

@Service
public class ProductService {
    private final ProductRepository repository;

    public ProductService(ProductRepository repository){
        this.repository = repository;
    }

    public void getAverageConsumption() {
    }
}

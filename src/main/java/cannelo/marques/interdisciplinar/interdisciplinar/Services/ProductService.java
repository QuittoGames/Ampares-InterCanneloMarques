package cannelo.marques.interdisciplinar.interdisciplinar.Services;

import org.springframework.stereotype.Service;

import cannelo.marques.interdisciplinar.interdisciplinar.Repository.ProductRepository;

@Service
public class ProductService {
    private final ProductRepository repository;

    public ProductService(ProductRepository repository){
        this.repository = repository;
    }
}
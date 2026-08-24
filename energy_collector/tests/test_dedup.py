from collector.models import Product


def test_primary_key_uses_source_id():
    p = Product(
        brand="Brand", model="ModelX", category="refrigerators", source_id="pd-123"
    )
    assert p.dedup_key() == "ENERGY STAR::pd-123"


def test_fallback_key_without_source_id():
    p = Product(brand="Brand", model="ModelX", category="refrigerators")
    assert p.dedup_key() == "ENERGY STAR::Brand::ModelX::refrigerators"


def test_primary_key_wins_over_fallback_fields():
    # Even if brand/model differ, source_id dominates the key.
    p1 = Product(brand="A", model="B", category="cat", source_id="pd-1")
    p2 = Product(brand="C", model="D", category="cat", source_id="pd-1")
    assert p1.dedup_key() == p2.dedup_key()


def test_distinct_source_ids_are_distinct():
    p1 = Product(source_id="pd-1")
    p2 = Product(source_id="pd-2")
    assert p1.dedup_key() != p2.dedup_key()


def test_product_id_is_deterministic():
    p1 = Product(brand="A", model="B", category="cat", source_id="pd-1")
    p2 = Product(brand="A", model="B", category="cat", source_id="pd-1")
    assert p1.product_id() == p2.product_id()

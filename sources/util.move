module createdao::util {
    use sui::object::{Self, ID};

    public fun empty_ID():ID {
        object::id_from_address(@0x00)
    }

    public fun zero_address():address {
         @0x00
    }
}
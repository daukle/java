package com.example;

import java.io.FileWriter;

public final class CheapestExample {
    public static void main(String[] args) throws Exception {
        try (FileWriter out = new FileWriter("cheapest.txt")) {
            out.write("cheapest\n");
        }
    }
}

package com.example;

import java.io.FileWriter;

public final class NewestExample {
    public static void main(String[] args) throws Exception {
        try (FileWriter out = new FileWriter("newest.txt")) {
            out.write("newest\n");
        }
    }
}

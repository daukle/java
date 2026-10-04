package com.example;

import java.io.InputStream;
import java.nio.charset.StandardCharsets;

public final class Main {
    public static void main(String[] args) throws Exception {
        try (InputStream stream = Main.class.getResourceAsStream("/greeting.txt")) {
            if (stream == null) {
                throw new IllegalStateException("greeting.txt is not on the classpath");
            }
            System.out.println(new String(stream.readAllBytes(), StandardCharsets.UTF_8).trim());
        }
    }
}

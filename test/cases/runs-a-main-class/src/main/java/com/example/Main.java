package com.example;

import java.io.FileWriter;

public final class Main {
    public static void main(String[] args) throws Exception {
        try (FileWriter out = new FileWriter("ran.txt")) {
            out.write("daukle\n");
        }
    }
}

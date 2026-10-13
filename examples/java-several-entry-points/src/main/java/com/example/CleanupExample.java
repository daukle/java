package com.example;

public final class CleanupExample {
    public static void main(String[] args) {
        System.out.println("CleanupExample ran in " + System.getProperty("cleanup.mode", "default") + " mode");
    }
}

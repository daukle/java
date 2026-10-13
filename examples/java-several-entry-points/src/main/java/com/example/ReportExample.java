package com.example;

public final class ReportExample {
    public static void main(String[] args) {
        System.out.println("ReportExample ran in " + System.getProperty("cleanup.mode", "default") + " mode");
    }
}

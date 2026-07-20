package com.example.multileader;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.autoconfigure.jdbc.DataSourceAutoConfiguration;

// We define TWO datasources manually (one per leader), so disable the single
// auto-configured datasource.
@SpringBootApplication(exclude = DataSourceAutoConfiguration.class)
public class MultiLeaderApplication {

    public static void main(String[] args) {
        SpringApplication.run(MultiLeaderApplication.class, args);
    }
}

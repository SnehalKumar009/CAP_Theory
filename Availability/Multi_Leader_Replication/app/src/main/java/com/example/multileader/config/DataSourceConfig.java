package com.example.multileader.config;

import javax.sql.DataSource;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.boot.autoconfigure.jdbc.DataSourceProperties;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/**
 * Two independent datasources — one per leader. Both nodes are full read-write
 * primaries, so the app can write to EITHER of them.
 */
@Configuration
public class DataSourceConfig {

    @Bean
    @ConfigurationProperties("app.datasource.a")
    public DataSourceProperties nodeAProps() {
        return new DataSourceProperties();
    }

    @Bean
    @ConfigurationProperties("app.datasource.b")
    public DataSourceProperties nodeBProps() {
        return new DataSourceProperties();
    }

    @Bean
    public DataSource nodeADataSource() {
        return nodeAProps().initializeDataSourceBuilder().build();
    }

    @Bean
    public DataSource nodeBDataSource() {
        return nodeBProps().initializeDataSourceBuilder().build();
    }

    @Bean
    public JdbcTemplate nodeAJdbc(@Qualifier("nodeADataSource") DataSource ds) {
        return new JdbcTemplate(ds);
    }

    @Bean
    public JdbcTemplate nodeBJdbc(@Qualifier("nodeBDataSource") DataSource ds) {
        return new JdbcTemplate(ds);
    }
}

package com.example.asyncrepl.repository;

import com.example.asyncrepl.entity.RecordEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RecordRepository extends JpaRepository<RecordEntity, Long> {
}

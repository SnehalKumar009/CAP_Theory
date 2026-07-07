package com.example.syncrepl.repository;

import com.example.syncrepl.entity.RecordEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RecordRepository extends JpaRepository<RecordEntity, Long> {
}

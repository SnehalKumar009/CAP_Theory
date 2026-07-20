package com.example.semisyncrepl.repository;

import com.example.semisyncrepl.entity.RecordEntity;
import org.springframework.data.jpa.repository.JpaRepository;

public interface RecordRepository extends JpaRepository<RecordEntity, Long> {
}

package com.example.semisyncrepl.controller;

import com.example.semisyncrepl.entity.RecordEntity;
import com.example.semisyncrepl.repository.RecordRepository;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

@RestController
@RequestMapping("/api/records")
public class RecordController {

    private final RecordRepository repository;

    public RecordController(RecordRepository repository) {
        this.repository = repository;
    }

    /**
     * WRITE path. With SEMI-SYNCHRONOUS replication (synchronous_standby_names =
     * 'ANY 1 (standby1, standby2)') the COMMIT blocks until AT LEAST ONE standby
     * confirms the WAL. So this succeeds as long as any one standby is alive
     * (kill one -> still works), but blocks only when ALL sync candidates are
     * down. The remaining standbys stream asynchronously.
     */
    @PostMapping("/write")
    public ResponseEntity<RecordEntity> write(@RequestBody WriteRequest request) {
        RecordEntity saved = repository.save(new RecordEntity(request.payload()));
        return ResponseEntity.ok(saved);
    }

    @GetMapping("/read")
    public List<RecordEntity> readAll() {
        return repository.findAll();
    }

    @GetMapping("/read/{id}")
    public ResponseEntity<RecordEntity> readOne(@PathVariable Long id) {
        return repository.findById(id)
                .map(ResponseEntity::ok)
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    public record WriteRequest(String payload) {
    }
}

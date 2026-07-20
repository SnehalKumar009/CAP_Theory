package com.example.asyncrepl.controller;

import com.example.asyncrepl.entity.RecordEntity;
import com.example.asyncrepl.repository.RecordRepository;
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
     * WRITE path. With ASYNCHRONOUS replication the COMMIT returns as soon as the
     * primary has flushed its own WAL — it does NOT wait for the standby. So this
     * call succeeds immediately even when the standby is down (Availability kept),
     * but those writes may not yet exist on the standby (Consistency relaxed).
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

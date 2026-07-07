package com.example.syncrepl.controller;

import com.example.syncrepl.entity.RecordEntity;
import com.example.syncrepl.repository.RecordRepository;
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
     * WRITE path. The COMMIT of this transaction blocks on the primary until a
     * synchronous standby acknowledges the WAL. If no standby can ack, this call
     * hangs (Consistency chosen over Availability) — that is the core CAP demo.
     */
    @PostMapping("/write")
    public ResponseEntity<RecordEntity> write(@RequestBody WriteRequest request) {
        RecordEntity saved = repository.save(new RecordEntity(request.payload()));
        return ResponseEntity.ok(saved);
    }

    /**
     * READ path. Reads keep working during a standby outage because the primary
     * is still serving. Demonstrates partial availability.
     */
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

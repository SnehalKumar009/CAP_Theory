package com.example.multileader.controller;

import java.util.List;
import java.util.Map;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Write to EITHER leader (node = "a" or "b"). Because replication is
 * bidirectional, a write on one node should appear on the other — until a
 * conflict occurs (see DEMO.md).
 */
@RestController
@RequestMapping("/api/records")
public class RecordController {

    private final JdbcTemplate nodeA;
    private final JdbcTemplate nodeB;

    public RecordController(@Qualifier("nodeAJdbc") JdbcTemplate nodeA,
                            @Qualifier("nodeBJdbc") JdbcTemplate nodeB) {
        this.nodeA = nodeA;
        this.nodeB = nodeB;
    }

    private JdbcTemplate pick(String node) {
        return "b".equalsIgnoreCase(node) ? nodeB : nodeA;
    }

    @PostMapping("/write/{node}")
    public ResponseEntity<Map<String, Object>> write(@PathVariable String node,
                                                      @RequestBody WriteRequest request) {
        JdbcTemplate jdbc = pick(node);
        Map<String, Object> row = jdbc.queryForMap(
                "INSERT INTO records(payload, origin_node) VALUES (?, ?) RETURNING id, payload, origin_node, created_at",
                request.payload(), node.toUpperCase());
        return ResponseEntity.ok(row);
    }

    @GetMapping("/read/{node}")
    public List<Map<String, Object>> read(@PathVariable String node) {
        return pick(node).queryForList("SELECT id, payload, origin_node, created_at FROM records ORDER BY id");
    }

    public record WriteRequest(String payload) {
    }
}

#!/usr/bin/env node

const http = require("http");
const https = require("https");
const { execSync } = require("child_process");

// Configuration
const maxAttempts = parseInt(process.env.SMOKE_TEST_ATTEMPTS || "20", 10);
const initialDelayMs = parseInt(process.env.SMOKE_TEST_INITIAL_DELAY_MS || "10000", 10);
const maxDelayMs = 60000;

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function getLoadBalancerUrl() {
    // Get the ALB URL from Pulumi stack output
    const urlFromEnv = process.env.SHOPPOLLAMA_URL;
    if (urlFromEnv) {
        return urlFromEnv;
    }

    try {
        console.log("Fetching load balancer URL from Pulumi stack outputs...");
        const output = execSync("pulumi stack output loadBalancerUrl --json", {
            encoding: "utf-8",
            cwd: __dirname,
        });
        return JSON.parse(output);
    } catch (err) {
        console.error("Failed to get Pulumi output. Using fallback or provide SHOPPOLLAMA_URL env var.");
        throw new Error("Could not determine load balancer URL");
    }
}

function makeRequest(url) {
    return new Promise((resolve, reject) => {
        const protocol = url.startsWith("https") ? https : http;
        const timeout = 15000;

        const req = protocol.get(
            url,
            {
                timeout,
                headers: {
                    "User-Agent": "shoppollama-smoke-test/1.0",
                    "Accept": "text/html,application/json,*/*",
                },
            },
            (res) => {
                const { statusCode } = res;
                let data = "";

                res.on("data", (chunk) => {
                    data += chunk;
                });

                res.on("end", () => {
                    if (statusCode && statusCode >= 200 && statusCode < 400) {
                        resolve({ statusCode, data: data.substring(0, 200) });
                    } else {
                        reject(new Error(`HTTP ${statusCode}: ${data.substring(0, 100)}`));
                    }
                });
            }
        );

        req.on("timeout", () => {
            req.destroy(new Error("Request timed out"));
        });

        req.on("error", (err) => reject(err));
    });
}

async function runSmokeTest() {
    console.log("=".repeat(60));
    console.log("SHOPPOLLAMA SMOKE TEST");
    console.log("=".repeat(60));

    let baseUrl;
    try {
        baseUrl = getLoadBalancerUrl();
    } catch (err) {
        console.error(`Error: ${err.message}`);
        process.exit(1);
    }

    console.log(`Target URL: ${baseUrl}`);
    console.log(`Max attempts: ${maxAttempts}`);
    console.log(`Initial delay: ${initialDelayMs}ms`);
    console.log("-".repeat(60));

    // Wait for initial setup (EC2 user data to complete)
    console.log(`\nWaiting ${initialDelayMs / 1000}s for infrastructure to initialize...`);
    await sleep(initialDelayMs);

    let delayMs = 5000;
    let lastError = null;

    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        const timestamp = new Date().toISOString();
        console.log(`\n[${timestamp}] Attempt ${attempt}/${maxAttempts}`);

        try {
            const result = await makeRequest(baseUrl);
            console.log(`SUCCESS: HTTP ${result.statusCode}`);
            console.log(`Response preview: ${result.data}...`);
            console.log("\n" + "=".repeat(60));
            console.log("SMOKE TEST PASSED!");
            console.log("=".repeat(60));
            console.log(`\nApplication is healthy at: ${baseUrl}`);
            process.exit(0);
        } catch (err) {
            lastError = err.message || String(err);
            console.log(`FAILED: ${lastError}`);

            if (attempt < maxAttempts) {
                console.log(`Retrying in ${delayMs / 1000}s...`);
                await sleep(delayMs);
                delayMs = Math.min(delayMs * 1.5, maxDelayMs);
            }
        }
    }

    console.log("\n" + "=".repeat(60));
    console.log("SMOKE TEST FAILED!");
    console.log("=".repeat(60));
    console.log(`\nApplication at ${baseUrl} did not become healthy.`);
    console.log(`Last error: ${lastError}`);
    console.log("\nTroubleshooting steps:");
    console.log("1. Check EC2 instance logs: aws ec2 get-console-output --instance-id <id>");
    console.log("2. Check target group health: aws elbv2 describe-target-health --target-group-arn <arn>");
    console.log("3. SSH into instance and check Docker: docker logs shoppollama");
    process.exit(1);
}

// Run the smoke test
runSmokeTest().catch((err) => {
    console.error("Unexpected error:", err);
    process.exit(1);
});

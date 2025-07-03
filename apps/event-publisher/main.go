package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"net/http" // Standard library HTTP
	"os"

	"github.com/cloudevents/sdk-go/v2/client"
	"github.com/cloudevents/sdk-go/v2/event"
	"github.com/google/uuid"

	// Import the CloudEvents HTTP protocol with an alias to avoid name collision
	cehttp "github.com/cloudevents/sdk-go/v2/protocol/http"
)

var (
	// K_SINK is an environment variable injected by Knative
	// that specifies the address of the event sink (e.g., a broker).
	sinkURL  string
	ceClient client.Client
)

func main() {
	sinkURL = os.Getenv("K_SINK")
	if sinkURL == "" {
		log.Fatal("K_SINK environment variable not set. This app is meant to run in a Knative environment.")
	}

	p, err := cehttp.New(cehttp.WithTarget(sinkURL))
	if err != nil {
		log.Fatalf("failed to create http protocol: %v", err)
	}

	ceClient, err = client.New(p, client.WithTimeNow(), client.WithUUIDs())
	if err != nil {
		log.Fatalf("failed to create cloudevents client: %v", err)
	}

	http.HandleFunc("/", handleRequest)
	log.Println("Publisher listening on port 8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatalf("failed to start server: %v", err)
	}
}

func handleRequest(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Only POST method is accepted", http.StatusMethodNotAllowed)
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		http.Error(w, "Error reading request body", http.StatusInternalServerError)
		return
	}
	defer r.Body.Close()

	message := string(body)
	log.Printf("Received message to publish: %s", message)

	e := event.New()
	e.SetID(uuid.New().String())
	e.SetType("com.example.ping")
	e.SetSource("knative-demo-publisher")
	if err := e.SetData(event.ApplicationJSON, map[string]string{"message": message}); err != nil {
		http.Error(w, "Failed to set event data", http.StatusInternalServerError)
		log.Printf("failed to set data: %v", err)
		return
	}

	// Send the event and check for a non-nil error, which represents a NACK.
	ctx := context.Background()
	if result := ceClient.Send(ctx, e); result != nil {
		http.Error(w, "Failed to send event", http.StatusInternalServerError)
		log.Printf("failed to send event, received NACK: %v", result)
		return
	}

	log.Printf("Successfully sent CloudEvent with message: %s", message)
	fmt.Fprintf(w, "Event published with message: %s\n", message)
}

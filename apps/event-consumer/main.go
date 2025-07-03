package main

import (
	"context"
	"log"

	"github.com/cloudevents/sdk-go/v2/client"
	"github.com/cloudevents/sdk-go/v2/event"
	cehttp "github.com/cloudevents/sdk-go/v2/protocol/http"
)

// receiveEvent is the handler for incoming CloudEvents.
func receiveEvent(ctx context.Context, e event.Event) {
	log.Printf("☁️  cloudevent received:")
	log.Printf("  ID: %s", e.ID())
	log.Printf("  Type: %s", e.Type())
	log.Printf("  Source: %s", e.Source())

	data := &struct {
		Message string `json:"message"`
	}{}

	if err := e.DataAs(data); err != nil {
		log.Printf("❌ got error while decoding data: %s", err.Error())
		return
	}

	log.Printf("  Data: %s", data.Message)
	log.Println("✅ cloudevent processed successfully")
}

func main() {
	// 1. Create the HTTP protocol.
	p, err := cehttp.New()
	if err != nil {
		log.Fatalf("failed to create protocol: %v", err)
	}

	// 2. Create the CloudEvents client from the protocol.
	c, err := client.New(p)
	if err != nil {
		log.Fatalf("failed to create client: %v", err)
	}
	// ------------------------------------

	log.Println("👋 consumer is ready to receive events on port 8080")

	if err := c.StartReceiver(context.Background(), receiveEvent); err != nil {
		log.Fatalf("failed to start receiver: %s", err)
	}
}

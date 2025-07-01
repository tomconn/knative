package main

import (
	"context"
	"log"
	"os"

	cloudevents "github.com/cloudevents/sdk-go/v2"
)

// receiveHandler is the main function that processes incoming HTTP requests.
// The CloudEvents SDK provides a convenient http.Handler that does all the work.
func receiveHandler(ctx context.Context, event cloudevents.Event) {
	// This function is now the *target* of the event, not the raw HTTP handler.
	// The SDK handles all the HTTP parsing and gives us a clean event object.

	// Log the key attributes of the received event.
	log.Println("Received a CloudEvent!")
	log.Printf("  - Type: %s", event.Type())
	log.Printf("  - Source: %s", event.Source())
	log.Printf("  - Subject: %s", event.Subject())
	log.Printf("  - Data: %s", string(event.Data()))
}

func main() {
	// Knative provides a PORT environment variable that our application must listen on.
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080" // Default to 8080 if PORT is not set.
	}

	// The NewClientHTTP() creates a new client that handles the HTTP protocol binding.
	// This is the standard way to create an event receiver.
	client, err := cloudevents.NewClientHTTP()
	if err != nil {
		log.Fatalf("Failed to create client, %v", err)
	}

	log.Printf("knative-event-display: starting server...")
	log.Printf("knative-event-display: listening on port %s", port)

	// The client.StartReceiver method is a blocking call that starts an HTTP server
	// and automatically routes incoming CloudEvents to our 'receiveHandler' function.
	// This replaces the manual http.ListenAndServe and http.HandleFunc.
	if err := client.StartReceiver(context.Background(), receiveHandler); err != nil {
		log.Fatalf("failed to start receiver: %v", err)
	}
}

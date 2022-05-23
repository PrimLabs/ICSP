module{
    public type HeaderField = (Text, Text);
    public type CallbackToken = {
        index: Nat;
        max_index: Nat;
        key: Text;
    };
    public type StreamingCallbackHttpResponse = {
        body: Blob;
        token: ?CallbackToken;
    };
    public type StreamStrategy = {
        #Callback: {
            callback: query (CallbackToken) -> async (StreamingCallbackHttpResponse);
            token: CallbackToken;
        }
    };
    public type HttpRequest = {
        method: Text;
        url: Text;
        headers: [HeaderField];
        body: Blob;
    };
    public type HttpResponse = {
        status_code: Nat16;
        headers: [HeaderField];
        body: Blob;
        streaming_strategy: ?StreamStrategy;
    };

}
package io.endigo.plugins.pdfviewflutter;

import android.app.Activity;
import android.content.Context;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;

public class PDFViewFlutterPlugin implements FlutterPlugin {
    MethodChannel channel;
    static PdfToImageInBackground pdfToImageInBackground;


    /**
     * Plugin registration.
     */
    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        binding
                .getPlatformViewRegistry()
                .registerViewFactory("plugins.endigo.io/pdfview", new PDFViewFactory(binding.getBinaryMessenger()));


        setupMethodChannel(binding.getBinaryMessenger(), binding.getApplicationContext());
    }

    private void setupMethodChannel(BinaryMessenger messenger, Context context) {
        channel = new MethodChannel(messenger, "Pdf_To_Image");
        final MethodCallHandlerImpl handler =
                new MethodCallHandlerImpl(context);
        channel.setMethodCallHandler(handler);
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        channel = null;
    }
}

class MethodCallHandlerImpl implements MethodChannel.MethodCallHandler {
    Context context;
//    static PdfToImageInBackground pdfToImageInBackground;

    MethodCallHandlerImpl(Context context/* PdfToImageInBackground pdfToImageInBackground*/) {
        this.context = context;
//        MethodCallHandlerImpl.pdfToImageInBackground = pdfToImageInBackground;
    }

    @Override
    public void onMethodCall(MethodCall call, @NonNull MethodChannel.Result result) {
        if (call.method.equals("getPdfThumbNail")) {
            new PdfThumbNail(context, call, result);
        } else if (call.method.equals("PdfToImage")) {
            new PdfToImage(context, call, result);
        } else if (call.method.equals("cancelPdfToImage")) {
            PDFViewFlutterPlugin.pdfToImageInBackground.cancel(true);
        } else {
            result.notImplemented();
        }
    }
}
package io.endigo.plugins.pdfviewflutter;

import android.content.Context;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.AsyncTask;
import android.os.ParcelFileDescriptor;
import android.text.TextUtils;

import com.shockwave.pdfium.PdfDocument;
import com.shockwave.pdfium.PdfPasswordException;
import com.shockwave.pdfium.PdfiumCore;

import java.io.File;
import java.io.FileOutputStream;
import java.util.ArrayList;
import java.util.HashMap;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel.Result;

public class PdfToImage {
    MethodCall call;
    public static MethodResultWrapper result;
    Context context;
//    PdfToImageInBackground pdfToImageInBackground;

    PdfToImage(Context context, MethodCall call, Result result) {
        this.context = context;
        this.call = call;
        PdfToImage.result = new MethodResultWrapper(result);
        new PdfToImage();
    }

    private PdfToImage() {
        HashMap<String, Object> arguments = (HashMap<String, Object>) call.arguments;

        File pdfFile = new File((String) arguments.get("pdfFilePath"));
        File destDir = new File((String) arguments.get("destFolderPath"));
        String password = (String) arguments.get("password");
        int maxSize = (int) arguments.get("maxSize");
        int compressValue = (int) arguments.get("compressValue");
        Uri pdfUri = Uri.fromFile(pdfFile);

        PdfToImageParams params = new PdfToImageParams(context, destDir, pdfUri, password, maxSize, compressValue, result);
        PDFViewFlutterPlugin.pdfToImageInBackground = new PdfToImageInBackground();
        PDFViewFlutterPlugin.pdfToImageInBackground.execute(params);
    }
}

class PdfToImageInBackground extends AsyncTask<PdfToImageParams, Integer, String> {

    @Override
    protected String doInBackground(PdfToImageParams... params) {
        try {
            ArrayList<String> imagePathList = openPdf(params[0]);
            params[0].result.success(imagePathList);
        } catch (Throwable throwable) {
            throwable.printStackTrace();
            if (throwable instanceof PdfPasswordException) {
                params[0].result.error("incorrect password", "Password required or incorrect password", null);
            } else {
                params[0].result.error("error", throwable.getMessage(), null);
            }
        }
        return "";
    }


    public ArrayList<String> openPdf(PdfToImageParams params) throws Throwable {
        ArrayList<String> imagePathList = new ArrayList<>();

        PdfDocument pdfDocument = null;
        ParcelFileDescriptor fd = params.context.getContentResolver().openFileDescriptor(params.pdfUri, "r");
        PdfiumCore pdfiumCore = new PdfiumCore(params.context);

        if (TextUtils.isEmpty(params.password)) {
            pdfDocument = pdfiumCore.newDocument(fd);
        } else {
            pdfDocument = pdfiumCore.newDocument(fd, params.password);
        }

        final int pageCount = pdfiumCore.getPageCount(pdfDocument);

        pdfiumCore.closeDocument(pdfDocument);
        if (fd != null)
            fd.close();

        try {
            for (int i = 0; i < pageCount; i++) {
                if (isCancelled()) {
                    imagePathList.clear();
                    break;
                }
                fd = params.context.getContentResolver().openFileDescriptor(params.pdfUri, "r");
                if (TextUtils.isEmpty(params.password)) {
                    pdfDocument = pdfiumCore.newDocument(fd);
                } else {
                    pdfDocument = pdfiumCore.newDocument(fd, params.password);
                }
                pdfiumCore.openPage(pdfDocument, i);
                int width = pdfiumCore.getPageWidth(pdfDocument, i);
                int height = pdfiumCore.getPageHeight(pdfDocument, i);

                int[] size = resize(width, height, params.maxSize, params.maxSize);
                width = size[0];
                height = size[1];

                Bitmap bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.RGB_565);
                pdfiumCore.renderPageBitmap(pdfDocument, bitmap, i, 0, 0, width, height, true);
                imagePathList.add(saveBitmap(bitmap, i, params.destDir, params.compressValue));
                recycleBitmap(bitmap);

                pdfiumCore.closeDocument(pdfDocument);
                if (fd != null)
                    fd.close();
                if (isCancelled()) {
                    imagePathList.clear();
                    i = pageCount;
                }
            }
        } finally {
            if (fd != null)
                fd.close();
        }
        return imagePathList;
    }

    public String saveBitmap(Bitmap bitmap, int index, File destDir, int compressValue) {
        File dest = new File(destDir, String.valueOf(index) + ".jpeg");
        FileOutputStream out = null;
        try {
            out = new FileOutputStream(dest);
            bitmap.compress(Bitmap.CompressFormat.JPEG, compressValue, out);
            out.flush();
            out.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return dest.getPath();
    }


    private static int[] resize(int width, int height, int maxWidth, int maxHeight) {
        if (Math.max(width, height) <= Math.max(maxWidth, maxHeight)) {
            return new int[]{width, height};
        }
        float ratioBitmap = (float) width / (float) height;
        float ratioMax = (float) maxWidth / (float) maxHeight;

        int finalWidth = maxWidth;
        int finalHeight = maxHeight;
        if (ratioMax > ratioBitmap) {
            finalWidth = (int) ((float) maxHeight * ratioBitmap);
        } else {
            finalHeight = (int) ((float) maxWidth / ratioBitmap);
        }
        return new int[]{finalWidth, finalHeight};
    }

    public static void recycleBitmap(Bitmap resizedBitmap) {
        try {
            if (resizedBitmap != null) {
                resizedBitmap.recycle();
            }
        } catch (Exception ignored) {

        }
    }


    // Always same signature
    @Override
    public void onPreExecute() {
    }

    @Override
    protected void onCancelled() {
    }

    @Override
    public void onPostExecute(String result) {
        super.onPostExecute(result);
    }

    @Override
    public void onProgressUpdate(Integer... parameters) {
        // Show in spinner, and access UI elements
    }

}

class PdfToImageParams {
    Context context;
    File destDir;
    Uri pdfUri;
    String password;
    int maxSize;
    int compressValue;
    MethodResultWrapper result;

    PdfToImageParams(Context context,
                     File destDir, Uri pdfUri, String password, int maxSize, int compressValue, MethodResultWrapper result) {
        this.context = context;
        this.destDir = destDir;
        this.pdfUri = pdfUri;
        this.password = password;
        this.maxSize = maxSize;
        this.compressValue = compressValue;
        this.result = result;
    }
}
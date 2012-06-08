
#include <cfloat>
#include "cu-kernels.h"



/*
 * CUDA kernels
 */


/*
 * CuMatrix
 */
template<typename Real>
__global__
static void _set_const(Real* mat, Real value, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows )
    mat[index] = value;
}


template<typename Real>
__global__
static void _apply_log(Real* mat, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows )
    mat[index] = log(mat[index]);
}


template<typename Real>
__global__
static void _apply_mask(Real* mat, const char* mask, MatrixDim dmat, MatrixDim dmask) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*dmat.stride;
  int32_cuda index2 = i + j*dmask.stride;
  if ( i < dmat.cols  &&  j < dmat.rows ) 
    if(mask[index2] == 0) mat[index] = 0;
}


template<typename Real>
__global__
static void _regularize_l1(Real* wei, Real* grad, Real l1, Real lr, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows ) {

    if(wei[index]==0.0) return; //skip L1 if zero weight!
    
    Real l1_signed = l1;
    if(wei[index] < 0.0) //flip sign
      l1_signed = -l1;

    Real before = wei[index];
    Real after = wei[index] -lr*grad[index] -l1_signed;//simulate update
    if((after > 0.0) ^ (before > 0.0)) { //sign changed?
      wei[index] = 0.0;
      grad[index] = 0.0;
    } else {
      wei[index] -= l1_signed;
    }
  }
}


template<typename Real>
__global__
static void _scale_cols(Real* mat, const Real* scale, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows )
    mat[index] *= scale[i];
}


template<typename Real>
__global__
static void _scale_rows(Real* mat, const Real* scale, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows )
    mat[index] *= scale[j];
}


template<typename Real>
__global__
static void _div_rows_vec(Real* mat, const Real* vec_div, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;

  if( j >= d.rows ) return;

  //invert divider in shared memory
  __shared__ Real inv[16];
  if(threadIdx.x==0) {
    inv[threadIdx.y] = 1.0/vec_div[j];
  }
  __syncthreads();
 
  //multiply elements
  if ( i < d.cols  &&  j < d.rows )
    mat[index] *= inv[threadIdx.y];
}


template<typename Real>
__global__
static void _add_scaled(Real alpha, const Real* A, Real beta, Real* dst, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows )
    dst[index] = alpha*A[index] + beta*dst[index];
}


template<typename Real>
__global__
static void _add_scaled_row(Real alpha, const Real* row, Real beta, Real* dst, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows )
    dst[index] = alpha*row[i] + beta*dst[index];
}


template<typename Real>
__global__
static void _mul_elem(Real* mat, const Real* A, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows )
    mat[index] = mat[index] * A[index];
}





/*
 * CuVector
 */
template<typename Real>
__global__
static void _add_col_sum(Real alpha, const Real* mat, Real beta, Real* vec, MatrixDim d) {

  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;

  //This should be called 1-D
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  if(j > 0) return;
  
  if(i < d.cols) {
    double sum = 0.0;
    for(int32_cuda k = 0; k < d.rows; k++) {
      sum += mat[i+k*d.stride];
    }
    vec[i] = alpha*sum + beta*vec[i];
  }
}


template<typename Real>
__global__
static void _add_col_sum_reduce(Real alpha, const Real* mat, Real beta, Real* vec, MatrixDim d) {

  //flipped x,y for reducing... x..row, y..col
  int32_cuda j = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda i = blockIdx.y * blockDim.y + threadIdx.y;

  if(blockIdx.x > 0) return;
  if(blockDim.y != 1) return;

  //copy vector to shared mem
  __shared__ Real aux[512];
  aux[threadIdx.x] = mat[i+j*d.stride];
  __syncthreads();

  Real sum = _sum_reduce(aux);
  __syncthreads();
  //copy out the result
  vec[i] = alpha*sum + beta*vec[i];
}


template<typename Real>
__global__
static void _invert_elements(Real* data, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows )
    data[index] = 1.0/data[index];
}



/*
 * cu::
 */
template<typename Real>
__global__
static void _sigmoid(Real*y, const Real*x, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if( i < d.cols  &&  j < d.rows ) {
    Real res = 1.0 / (1.0 + exp(-x[index]));
    /*
    if(res < 0.001) res = 0.001;
    if(res > 0.999) res = 0.999;
    */
    y[index] = res;
  }
}


template<typename Real>
__global__
static void _diff_sigmoid(Real*eout, const Real*e, const Real*y, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if( i < d.cols  && j < d.rows ) 
    eout[index] = y[index]*(1.0-y[index]) * e[index];
}


template<typename Real>
__global__
static void _softmax(Real*y, const Real*x, MatrixDim d) {
  int32_cuda j = blockIdx.x * blockDim.x + threadIdx.x;
  if(j >= d.rows) return;

  //copy to output and find max...
  double max = -1e20;
  double sum = 0.0;
  for(int32_cuda i=0; i<d.cols; i++) {
    if(max < x[i+j*d.stride]) max = x[i+j*d.stride];
    y[i+j*d.stride] = x[i+j*d.stride];
  }
  //subtract max, apply exp, sum up...
  for(int32_cuda i=0; i<d.cols; i++) {
    y[i+j*d.stride] = exp(y[i+j*d.stride] - max);
    sum += y[i+j*d.stride];
  }
  //normalize by sum...
  for(int32_cuda i=0; i<d.cols; i++) {
    y[i+j*d.stride] /= sum;
  }
}




template<typename Real>
__device__
static Real _max_reduce(Real buffer[]) {

  // Total number of active threads
  int32_cuda nTotalThreads = blockDim.x;	
  __syncthreads();

  while(nTotalThreads > 1) {
    int32_cuda halfPoint = ((1+nTotalThreads) >> 1);	// divide by two
    // only the first half of the threads will be active.
    if (threadIdx.x < halfPoint)  {
      // Get the shared value stored by another thread
      Real temp = -1e20;
      if(threadIdx.x+halfPoint < nTotalThreads) {
        temp = buffer[threadIdx.x + halfPoint];
      }
      if (temp > buffer[threadIdx.x]) buffer[threadIdx.x] = temp;
    }
    __syncthreads();
    nTotalThreads = ((1+nTotalThreads) >> 1);	// divide by two.
  }
  // the result
  return buffer[0];
}




template<typename Real>
__device__
static Real _sum_reduce(Real buffer[]) {

  // Total number of active threads
  int32_cuda nTotalThreads = blockDim.x;	
  __syncthreads();

  while(nTotalThreads > 1) {
    int32_cuda halfPoint = ((1+nTotalThreads) >> 1);	// divide by two
    // only the first half of the threads will be active.
    if (threadIdx.x < halfPoint)  {
      // Get the shared value stored by another thread
      Real temp = 0.0;
      if(threadIdx.x+halfPoint < nTotalThreads) {
        temp = buffer[threadIdx.x + halfPoint];
      }
      buffer[threadIdx.x] += temp;
    }
    __syncthreads();
    nTotalThreads = ((1+nTotalThreads) >> 1);	// divide by two.
  }
  // the result
  return buffer[0];
}



template<typename Real>
__global__
static void _softmax_reduce(Real*y, const Real*x, MatrixDim d) {
  
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;

  if(blockIdx.x > 0) return;
  if(blockDim.y > 1) return;

  __shared__ Real row_data[256];
  __shared__ Real aux[256];

  //copy the input to row_data
  row_data[i] = x[i+j*d.stride];
  __syncthreads();

  //copy input to aux
  aux[i] = row_data[i];
  __syncthreads();
  //get the maximum value
  Real max = _max_reduce(aux);
  __syncthreads();

  //calculate exp(data-max)
  row_data[i] = exp(row_data[i]-max);
 
  //copy the values to aux
  aux[i] = row_data[i];
  __syncthreads();
  //get the sum
  Real sum = _sum_reduce(aux);
  __syncthreads();

  //divide the values
  row_data[i] /= sum;
  //copy out
  y[i+j*d.stride] = row_data[i];

}



template<typename Real>
__global__
static void _expand(Real* y, const Real* x, const int32_cuda* off, MatrixDim d_out, MatrixDim d_in)
{
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d_out.stride;
  if( i < d_out.cols  && j < d_out.rows ) {
    int32_cuda src_col = i % d_in.cols;
    int32_cuda src_row = j + off[i / d_in.cols];
    if(src_row < 0) src_row = 0;
    if(src_row >= d_in.rows) src_row = d_in.rows-1;
    y[index] = x[src_col + src_row*d_in.stride];
  }
}


template<typename Real>
__global__
static void _rearrange(Real* y, const Real* x, const int32_cuda* copy_from, MatrixDim d_out, MatrixDim d_in)
{
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d_out.stride;
  if( i < d_out.cols  && j < d_out.rows ) {
    int32_cuda src_col = copy_from[i];
    if(src_col >= 0 && src_col < d_in.cols) {
      y[index] = x[src_col + j*d_in.stride];
    } else {
      y[index] = 1.0/0.0;
    }
  }
}


template<typename Real>
__global__
static void _randomize(Real* y, const Real* x, const int32_cuda* copy_from, MatrixDim d_out, MatrixDim d_in)
{
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d_out.stride;
  if( i < d_out.cols  && j < d_out.rows ) {
    int32_cuda src_row = copy_from[j];
    y[index] = x[i + src_row*d_in.stride];
  }
}


template<typename Real>
__global__
static void _check_class(const Real* out, const Real* des, float* match, MatrixDim d)
{
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  if(j>0) return;

  if(i<d.rows) {
    int32_cuda out_id = -1, des_id = -2;
    Real out_max = -1e20, des_max = -1e20;

    for(int32_cuda k=0; k<d.cols; k++) {
      Real val = out[k + i*d.stride];
      if(val > out_max) { out_max = val; out_id = k; }
    }
    for(int32_cuda k=0; k<d.cols; k++) {
      Real val = des[k + i*d.stride];
      if(val > des_max) { des_max = val; des_id = k; }
    }
    
    match[i] = ((out_id == des_id)?1:0);
  }
}


template<typename Real>
__device__
static int32_cuda _max_id_reduce(Real val[], int32_cuda idx[]) {

  // Total number of active threads
  int32_cuda nTotalThreads = blockDim.x;	
  __syncthreads();

  while(nTotalThreads > 1) {
    int32_cuda halfPoint = ((1+nTotalThreads) >> 1);	// divide by two
    // only the first half of the threads will be active.
    if (threadIdx.x < halfPoint)  {
      // Get the shared value stored by another thread
      Real temp = -1e20;
      if(threadIdx.x+halfPoint < nTotalThreads) {
        temp = val[idx[threadIdx.x + halfPoint]];
      }
      if (temp > val[idx[threadIdx.x]]) idx[threadIdx.x]=idx[threadIdx.x + halfPoint];
    }
    __syncthreads();
    nTotalThreads = ((1+nTotalThreads) >> 1);	// divide by two.
  }
  // the result
  return idx[0];
}






template<typename Real>
__global__
static void _check_class_reduce(const Real* out, const Real* des, float* match, MatrixDim d)
{
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;

  if(blockIdx.x > 0) return;
  if(blockDim.y != 1) return;

  __shared__ Real value[256];
  __shared__ int32_cuda index[256];

  value[threadIdx.x] = out[i+j*d.stride];
  index[threadIdx.x] = threadIdx.x;
  __syncthreads();

  int32_cuda out_max = _max_id_reduce(value,index);
  __syncthreads();

  value[threadIdx.x] = des[i+j*d.stride];
  index[threadIdx.x] = threadIdx.x;
  __syncthreads();
  
  int32_cuda des_max = _max_id_reduce(value,index);
  __syncthreads();

  if(threadIdx.x == 0) {
    match[j] = ((out_max == des_max)?1:0);
  }
}



template<typename Real>
__global__
static void _find_row_max_id(const Real* mat, Real* vec_val, int32_cuda* vec_id, int32_cuda voff, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;

  if(blockIdx.x > 0) return;
  if(blockDim.y != 1) return;

  __shared__ Real value[256];
  __shared__ int32_cuda index[256];

  //copy to shared memory
  value[threadIdx.x] = mat[i+j*d.stride];
  index[threadIdx.x] = threadIdx.x;
  __syncthreads();
  
  //get the id of the max value
  int32_cuda out_max = _max_id_reduce(value,index);
  __syncthreads();

  //see if it's bigger value
  if(threadIdx.x == 0) {
    if(vec_val[j] <= mat[out_max+j*d.stride]) {
      vec_val[j] = mat[out_max+j*d.stride];
      vec_id[j]  = voff+out_max;
    }
  }
}


template<typename Real>
__global__
static void _diff_xent(const int32_cuda* vec_tgt, Real* mat_net_out, Real* vec_log_post, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;

  if(i>0) return;
  if(j<d.rows) {
    int32_cuda index = vec_tgt[j] + j*d.stride;
    Real value = mat_net_out[index];
    if(value < 1e-20) value = 1e-20;
    vec_log_post[j] = log(value);
    mat_net_out[index] -= 1.0;
  }
}


template<typename Real>
__global__
static void _softmax_part(const Real* X, const int32_cuda* vec_ids, Real* Y, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;
  int32_cuda index = i + j*d.stride;
  if ( i < d.cols  &&  j < d.rows ) {
    Real tmp = X[index] - X[vec_ids[j] + j*d.stride];
    Y[index] = exp(tmp);
  }
}


template<typename Real>
__global__
static void _sum_rows_vec(const Real* mat, Real* vec_sum, MatrixDim d) {
  int32_cuda i = blockIdx.x * blockDim.x + threadIdx.x;
  int32_cuda j = blockIdx.y * blockDim.y + threadIdx.y;

  if(blockIdx.x > 0) return;
  if(blockDim.y > 1) return;

  __shared__ Real row_data[256];

  //copy the input to row_data
  row_data[i] = mat[i+j*d.stride];
  __syncthreads();

  //get the sum
  Real sum = _sum_reduce(row_data);
  __syncthreads();
  
  //add to previously accumulated sum
  vec_sum[j] += sum;
}


/*
 * ANSI-C wrappers of CUDA kernels
 */

/*
 * float 
 */

/*
 * CuMatrix
 */
void cudaF_set_const(dim3 Gr, dim3 Bl, float* mat, float value, MatrixDim d) {
  _set_const<<<Gr,Bl>>>(mat,value,d); 
}

void cudaF_apply_log(dim3 Gr, dim3 Bl, float* mat, MatrixDim d) {
  _apply_log<<<Gr,Bl>>>(mat,d); 
}

void cudaF_apply_mask(dim3 Gr, dim3 Bl, float* mat, const char* mask, MatrixDim dmat, MatrixDim dmask) {
  _apply_mask<<<Gr,Bl>>>(mat,mask,dmat,dmask); 
}

void cudaF_scale_cols(dim3 Gr, dim3 Bl, float* mat, const float* scale, MatrixDim d) {
  _scale_cols<<<Gr,Bl>>>(mat,scale,d); 
}

void cudaF_scale_rows(dim3 Gr, dim3 Bl, float* mat, const float* scale, MatrixDim d) {
  _scale_rows<<<Gr,Bl>>>(mat,scale,d);
}

void cudaF_div_rows_vec(dim3 Gr, dim3 Bl, float* mat, const float* vec_div, MatrixDim d) {
  _div_rows_vec<<<Gr,Bl>>>(mat, vec_div, d);
}

void cudaF_add_scaled(dim3 Gr, dim3 Bl, float alpha, const float* A, float beta, float* dst, MatrixDim d) {
  _add_scaled<<<Gr,Bl>>>(alpha,A,beta,dst,d); 
}

void cudaF_add_scaled_row(dim3 Gr, dim3 Bl, float alpha, const float* row, float beta, float* dst, MatrixDim d) {
  _add_scaled_row<<<Gr,Bl>>>(alpha,row,beta,dst,d); 
}

void cudaF_mul_elem(dim3 Gr, dim3 Bl, float* mat, const float* A, MatrixDim d) {
  _mul_elem<<<Gr,Bl>>>(mat,A,d); 
}

/*
 * CuVector
 */
void cudaF_add_col_sum(size_t Gr, size_t Bl, float alpha, const float* mat, float beta, float* vec, MatrixDim d) {
  _add_col_sum<<<Gr,Bl>>>(alpha,mat,beta,vec,d); 
}

void cudaF_add_col_sum_reduce(dim3 Gr, dim3 Bl, float alpha, const float* mat, float beta, float* vec, MatrixDim d) {
  _add_col_sum_reduce<<<Gr,Bl>>>(alpha,mat,beta,vec,d); 
}

void cudaF_invert_elements(dim3 Gr, dim3 Bl, float* data, MatrixDim d) {
  _invert_elements<<<Gr,Bl>>>(data, d);
}

/*
 * cu::
 */
void cudaF_sigmoid (dim3 Gr, dim3 Bl, float* y, const float* x, MatrixDim d) {
  _sigmoid<<<Gr,Bl>>>(y, x, d); 
}

void cudaF_diff_sigmoid (dim3 Gr, dim3 Bl, float* eout, const float* e, const float* y, MatrixDim d) {
  _diff_sigmoid<<<Gr,Bl>>>(eout, e, y, d);
}

void cudaF_softmax (size_t Gr, size_t Bl, float* y, const float* x, MatrixDim d) { 
  _softmax<<<Gr,Bl>>>(y, x, d); 
}

void cudaF_softmax_reduce (dim3 Gr, dim3 Bl, float* y, const float* x, MatrixDim d) { 
  _softmax_reduce<<<Gr,Bl>>>(y, x, d); 
}


void cudaF_expand(dim3 Gr, dim3 Bl, float* y, const float* x, const int32_cuda* off, MatrixDim d_out, MatrixDim d_in) {
  _expand<<<Gr,Bl>>>(y,x,off,d_out,d_in); 
}


void cudaF_rearrange(dim3 Gr, dim3 Bl, float* y, const float* x, const int32_cuda* copy_from, MatrixDim d_out, MatrixDim d_in) {
  _rearrange<<<Gr,Bl>>>(y,x,copy_from,d_out,d_in); 
}

  
void cudaF_randomize(dim3 Gr, dim3 Bl, float* y, const float* x, const int32_cuda* copy_from, MatrixDim d_out, MatrixDim d_in) { 
  _randomize<<<Gr,Bl>>>(y,x,copy_from,d_out,d_in); 
}


void cudaF_check_class(size_t Gr, size_t Bl, const float* out, const float* des, float* match, MatrixDim d) { 
  _check_class<<<Gr,Bl>>>(out,des,match,d); 
}

void cudaF_check_class_reduce(dim3 Gr, dim3 Bl, const float* out, const float* des, float* match, MatrixDim d) { 
  _check_class_reduce<<<Gr,Bl>>>(out,des,match,d); 
}

void cudaF_regularize_l1(dim3 Gr, dim3 Bl, float* wei, float* grad, float l1, float lr, MatrixDim d) {
  _regularize_l1<<<Gr,Bl>>>(wei,grad,l1,lr,d); 
}


void cudaF_find_row_max_id(dim3 Gr, dim3 Bl, const float* mat, float* vec_val, int32_cuda* vec_id, int32_cuda voff, MatrixDim d) {
  _find_row_max_id<<<Gr,Bl>>>(mat, vec_val, vec_id, voff, d);
}

void cudaF_diff_xent(dim3 Gr, dim3 Bl, const int32_cuda* vec_tgt, float* mat_net_out, float* vec_log_post, MatrixDim d) {
  _diff_xent<<<Gr,Bl>>>(vec_tgt,mat_net_out,vec_log_post,d);
}

void cudaF_softmax_part(dim3 Gr, dim3 Bl, const float* X, const int32_cuda* vec_ids, float* Y, MatrixDim d) {
  _softmax_part<<<Gr,Bl>>>(X,vec_ids,Y,d);
}

void cudaF_sum_rows_vec(dim3 Gr, dim3 Bl, const float* mat, float* vec_sum, MatrixDim d) {
  _sum_rows_vec<<<Gr,Bl>>>(mat,vec_sum,d);
}


/*
 * int32 CUDA functions
 */
void cudaI32_set_const(dim3 Gr, dim3 Bl, int32_cuda* mat, int32_cuda value, MatrixDim d) {
  _set_const<<<Gr,Bl>>>(mat,value,d); 
}
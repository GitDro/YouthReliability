# Reliability developmental MRI

Contains data and analysis towards "Reliability of multimodal MRI brain measures in youth at risk for mental illness" by Drobinin et al.


## Getting started

#### To view the analysis:

1. Download the repository and extract.
2. Open `YouthReliability.nb.html` with any modern browser. This is the _knit_ or _rendered_ R notebook for quick and easy exploration with no installation requirements.

#### To run the analysis:

1. Download or clone the repository and extract.
2. Open the _R Project_ file `YouthReliability.Rproj`.
3. Open the _R Notebook_ if not already opened `YouthReliability.Rmd`
4. Click `Run All`


---

Note, running the notebook will check for required R packages and install them if missing. A minimum number of commonly used packages are required and they are summarized below.

```{r}
library(tidyverse) # ggplot, dplyr, tidyr, readr, purr, tibble
library(here) # here() starts at R Project directory, cross platform paths
library(lubridate) # working with dates
library(ICC) # ICC and CI
library(glue) # interpolate data into strings
```
